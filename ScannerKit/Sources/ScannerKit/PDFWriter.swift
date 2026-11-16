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
    /// Median text line height as a share of the image's long side, to estimate the size of pages that are not A4 or Letter.
    public var textLineHeight: Double?

    public init(image: CIImage, look: PageLook, textLineHeight: Double? = nil) {
        self.image = image
        self.look = look
        self.textLineHeight = textLineHeight
    }
}

public enum PDFWriterError: Error {
    case cannotCreateDocument
    case cannotEncodePage
}

/// Writes one image per page, encoded for its look as a grayscale or color JPEG.
public struct PDFWriter: @unchecked Sendable {
    private let context: CIContext
    private let sizing: PageSizing
    private let creator: String

    public init(context: CIContext, sizing: PageSizing = .init(), creator: String = "Roneograph") {
        self.context = context
        self.sizing = sizing
        self.creator = creator
    }

    public func data(pages: [PDFPageContent], title: String, quality: PDFQuality, defaultPaper: Paper) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: nil, [kCGPDFContextTitle: title, kCGPDFContextCreator: creator, kCGPDFContextCreatePDFA: true] as CFDictionary) else {
            throw PDFWriterError.cannotCreateDocument
        }
        for page in pages {
            let image = page.image.atOrigin
            var box = CGRect(origin: .zero, size: sizing.pageSize(forImage: image.extent.size, textLineHeight: page.textLineHeight, defaultPaper: defaultPaper))
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
        let resized = resample(image, to: CGSize(width: pageSize.width / 72 * quality.imageDPI, height: pageSize.height / 72 * quality.imageDPI))
        return try jpeg(resized, gray: look == .gray, quality: quality.jpegQuality)
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
}
