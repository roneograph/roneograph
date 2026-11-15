import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PDFQuality: String, Codable, Sendable, CaseIterable {
    case small, balanced, best

    var imageDPI: CGFloat {
        switch self {
        case .small, .balanced: 150
        case .best: 200
        }
    }

    var blackAndWhiteDPI: CGFloat {
        switch self {
        case .small: 200
        case .balanced, .best: 300
        }
    }

    var jpegQuality: Double {
        switch self {
        case .small: 0.3
        case .balanced: 0.5
        case .best: 0.65
        }
    }
}

public struct PDFPageContent: @unchecked Sendable {
    public var image: CIImage
    public var look: PageLook

    public init(image: CIImage, look: PageLook) {
        self.image = image
        self.look = look
    }
}

public enum PDFWriterError: Error {
    case cannotCreateDocument
    case cannotEncodePage
}

/// Writes one image per page, encoded for its look: grayscale JPEG, color JPEG, or lossless 1-bit.
public struct PDFWriter: @unchecked Sendable {
    private let context: CIContext
    private let sizing: PageSizing

    public init(context: CIContext, sizing: PageSizing = .init()) {
        self.context = context
        self.sizing = sizing
    }

    public func data(pages: [PDFPageContent], title: String, quality: PDFQuality, defaultPaper: Paper) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: nil, [kCGPDFContextTitle: title] as CFDictionary) else {
            throw PDFWriterError.cannotCreateDocument
        }
        for page in pages {
            let image = page.image.transformed(by: CGAffineTransform(translationX: -page.image.extent.minX, y: -page.image.extent.minY))
            var box = CGRect(origin: .zero, size: sizing.pageSize(forImage: image.extent.size, defaultPaper: defaultPaper))
            let encoded = try encode(image, look: page.look, pageSize: box.size, quality: quality)
            pdf.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            pdf.interpolationQuality = .high
            pdf.draw(encoded, in: box)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return data as Data
    }

    private func encode(_ image: CIImage, look: PageLook, pageSize: CGSize, quality: PDFQuality) throws -> CGImage {
        let dpi = look == .blackAndWhite ? quality.blackAndWhiteDPI : quality.imageDPI
        let resized = resample(image, to: CGSize(width: pageSize.width / 72 * dpi, height: pageSize.height / 72 * dpi))
        switch look {
        case .blackAndWhite:
            return try oneBit(resized)
        case .gray:
            return try jpeg(resized, gray: true, quality: quality.jpegQuality)
        case .color, .photo:
            return try jpeg(resized, gray: false, quality: quality.jpegQuality)
        }
    }

    /// Resamples to the target pixel size, or to the page proportions at the image's own resolution when it has fewer pixels.
    private func resample(_ image: CIImage, to target: CGSize) -> CIImage {
        let size = image.extent.size
        let k = min(1, max(size.width / target.width, size.height / target.height))
        let width = max(1, (target.width * k).rounded()), height = max(1, (target.height * k).rounded())
        let scaleY = height / size.height
        let scaled = image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scaleY, kCIInputAspectRatioKey: (width / size.width) / scaleY])
        return scaled.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private func jpeg(_ image: CIImage, gray: Bool, quality: Double) throws -> CGImage {
        let space = gray ? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let pixels = context.createCGImage(image, from: image.extent, format: gray ? .L8 : .RGBA8, colorSpace: space) else {
            throw PDFWriterError.cannotEncodePage
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PDFWriterError.cannotEncodePage
        }
        CGImageDestinationAddImage(destination, pixels, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        // A JPEG-backed image is embedded in the PDF as is, without being decoded and compressed again.
        guard CGImageDestinationFinalize(destination), let provider = CGDataProvider(data: data),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw PDFWriterError.cannotEncodePage
        }
        return jpeg
    }

    private func oneBit(_ image: CIImage) throws -> CGImage {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var gray = [UInt8](repeating: 0, count: width * height)
        context.render(image, toBitmap: &gray, rowBytes: width, bounds: image.extent, format: .L8, colorSpace: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))

        let rowBytes = (width + 7) / 8
        var bits = [UInt8](repeating: 0, count: rowBytes * height)
        for y in 0..<height {
            for x in 0..<width where gray[y * width + x] >= 128 {
                bits[y * rowBytes + x / 8] |= 0x80 >> UInt8(x % 8)
            }
        }
        guard let provider = CGDataProvider(data: Data(bits) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 1, bitsPerPixel: 1, bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw PDFWriterError.cannotEncodePage
        }
        return image
    }
}
