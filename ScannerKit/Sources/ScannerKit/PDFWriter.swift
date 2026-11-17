import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PDFPageContent: Sendable {
    public var image: CIImage
    public var look: PageLook
    /// Median text line height as a share of the image's long side, to estimate the size of pages that are not A4 or Letter.
    public var textLineHeight: Double?
    /// Drawn as invisible text over the image, so the page can be searched, selected and read aloud.
    public var text: [TextLine]

    public init(image: CIImage, look: PageLook, textLineHeight: Double? = nil, text: [TextLine] = []) {
        self.image = image
        self.look = look
        self.textLineHeight = textLineHeight
        self.text = text
    }
}

public enum PDFWriterError: Error {
    case cannotCreateDocument
    case cannotEncodePage
}

/// Writes one image per page, encoded for its look as a grayscale or color JPEG, under the invisible text of the page.
public struct PDFWriter: Sendable {
    private let context: CIContext
    private let sizing = PageSizing()
    private let creator = "Roneograph"
    private let dpi: CGFloat = 150
    private let jpegQuality = 0.5

    public init(context: CIContext) {
        self.context = context
    }

    public func data(pages: [PDFPageContent], title: String, defaultPaper: Paper) throws -> Data {
        let document = try document(title: title, defaultPaper: defaultPaper)
        for page in pages {
            try document.add(page)
        }
        return document.close()
    }

    /// A PDF written one page at a time, so the image of a page can be released once it is added.
    public func document(title: String, defaultPaper: Paper) throws -> Document {
        try Document(writer: self, title: title, defaultPaper: defaultPaper)
    }

    public final class Document {
        private let writer: PDFWriter
        private let defaultPaper: Paper
        private let data = NSMutableData()
        private let pdf: CGContext

        fileprivate init(writer: PDFWriter, title: String, defaultPaper: Paper) throws {
            self.writer = writer
            self.defaultPaper = defaultPaper
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let pdf = CGContext(consumer: consumer, mediaBox: nil, [kCGPDFContextTitle: title, kCGPDFContextCreator: writer.creator, kCGPDFContextCreatePDFA: true] as CFDictionary) else {
                throw PDFWriterError.cannotCreateDocument
            }
            self.pdf = pdf
        }

        public func add(_ page: PDFPageContent) throws {
            let image = page.image.atOrigin
            var box = CGRect(origin: .zero, size: writer.sizing.pageSize(forImage: image.extent.size, textLineHeight: page.textLineHeight, defaultPaper: defaultPaper))
            let resized = writer.resample(image, to: CGSize(width: box.width / 72 * writer.dpi, height: box.height / 72 * writer.dpi))
            let encoded = try writer.jpeg(resized, gray: page.look == .gray)
            pdf.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            pdf.draw(encoded, in: box)
            writer.drawInvisibly(page.text, in: pdf, pageSize: box.size)
            pdf.endPDFPage()
        }

        public func close() -> Data {
            pdf.closePDF()
            return data as Data
        }
    }

    /// Stretches each line over the box where it was read, so a selection covers the printed words.
    private func drawInvisibly(_ lines: [TextLine], in pdf: CGContext, pageSize: CGSize) {
        pdf.saveGState()
        pdf.setTextDrawingMode(.invisible)
        for line in lines where !line.text.isEmpty {
            let frame = CGRect(x: line.frame.minX * pageSize.width, y: (1 - line.frame.maxY) * pageSize.height, width: line.frame.width * pageSize.width, height: line.frame.height * pageSize.height)
            let font = CTFontCreateWithName("Helvetica" as CFString, frame.height, nil)
            let text = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(text, &ascent, &descent, nil)
            guard width > 0, ascent + descent > 0 else { continue }
            let scaleY = frame.height / (ascent + descent)
            pdf.saveGState()
            pdf.translateBy(x: frame.minX, y: frame.minY + descent * scaleY)
            pdf.scaleBy(x: frame.width / width, y: scaleY)
            pdf.textMatrix = .identity
            pdf.textPosition = .zero
            CTLineDraw(text, pdf)
            pdf.restoreGState()
        }
        pdf.restoreGState()
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

    private func jpeg(_ image: CIImage, gray: Bool) throws -> CGImage {
        let space = gray ? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let pixels = context.createCGImage(image, from: image.extent, format: gray ? .L8 : .RGBA8, colorSpace: space) else {
            throw PDFWriterError.cannotEncodePage
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PDFWriterError.cannotEncodePage
        }
        CGImageDestinationAddImage(destination, pixels, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        // A JPEG-backed image is embedded in the PDF as is, without being decoded and compressed again.
        guard CGImageDestinationFinalize(destination), let provider = CGDataProvider(data: data),
              let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw PDFWriterError.cannotEncodePage
        }
        return jpeg
    }
}
