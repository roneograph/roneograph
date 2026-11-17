import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import ImageIO
import Vision

/// Finds a page in an image and flattens it, with Vision and Core Image.
public struct PageExtractor: Sendable {
    private let context: CIContext

    public init(context: CIContext) {
        self.context = context
    }

    /// Detects a page in an upright image.
    public func detect(in image: CIImage) async -> Quad? {
        await detect(with: ImageRequestHandler(image))
    }

    /// Detects a page in a camera frame; the quad is relative to the frame once rotated by `orientation`.
    public func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) async -> Quad? {
        await detect(with: ImageRequestHandler(pixelBuffer, orientation: orientation))
    }

    /// Removes the perspective: the four corners become the corners of the output image, whose origin is zero.
    public func correct(_ image: CIImage, quad: Quad) -> CIImage {
        let extent = image.extent
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: extent.minX + p.x * extent.width, y: extent.maxY - p.y * extent.height)
        }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        filter.topLeft = point(quad.topLeft)
        filter.topRight = point(quad.topRight)
        filter.bottomRight = point(quad.bottomRight)
        filter.bottomLeft = point(quad.bottomLeft)
        return filter.outputImage?.atOrigin ?? image
    }

    /// A tiny fingerprint of the page content inside `quad`.
    public func signature(of image: CIImage, quad: Quad) -> PageSignature? {
        let page = correct(image, quad: quad)
        guard page.extent.width >= 1, page.extent.height >= 1 else { return nil }
        let width = PageSignature.width, height = PageSignature.height
        let scale = CGFloat(height) / page.extent.height
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = page
        filter.scale = Float(scale)
        filter.aspectRatio = Float((CGFloat(width) / page.extent.width) / scale)
        guard let small = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: width * height * 4)
        context.render(small, toBitmap: &bitmap, rowBytes: width * 4, bounds: CGRect(x: small.extent.minX, y: small.extent.minY, width: CGFloat(width), height: CGFloat(height)), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let luminance = stride(from: 0, to: bitmap.count, by: 4).map { (i: Int) -> Float in
            let red = 0.299 * Float(bitmap[i]), green = 0.587 * Float(bitmap[i + 1]), blue = 0.114 * Float(bitmap[i + 2])
            return (red + green + blue) / 255
        }
        return PageSignature(luminance: luminance)
    }

    public func jpegData(of image: CIImage, quality: Double) -> Data? {
        context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }

    private func detect(with handler: ImageRequestHandler) async -> Quad? {
        if let page = try? await handler.perform(DetectDocumentSegmentationRequest(.revision1)), page.confidence >= 0.5 {
            return Quad(page)
        }
        var rectangles = DetectRectanglesRequest(.revision1)
        rectangles.maximumObservations = 1
        rectangles.minimumAspectRatio = 0.2
        rectangles.maximumAspectRatio = 1
        rectangles.minimumSize = 0.2
        rectangles.quadratureToleranceDegrees = 30
        rectangles.minimumConfidence = 0.5
        if let page = try? await handler.perform(rectangles).first {
            return Quad(page)
        }
        return nil
    }
}

private extension Quad {
    init(_ observation: some QuadrilateralProviding) {
        self.init(lowerLeftOriginTopLeft: observation.topLeft.cgPoint, topRight: observation.topRight.cgPoint, bottomRight: observation.bottomRight.cgPoint, bottomLeft: observation.bottomLeft.cgPoint)
    }
}
