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

/// Writes one image per page under the invisible text of the page: a color page as a JPEG, a gray page as 16 lossless gray levels or as a JPEG, whichever is smaller.
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
            let encoded = try writer.encoded(resized, look: page.look)
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
        let scaled = image.clampedToExtent().applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scaleY, kCIInputAspectRatioKey: (width / size.width) / scaleY])
        return scaled.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Text on white paper is smaller in 16 gray levels, without the ringing of a JPEG around the letters; pictures are smaller as a JPEG.
    private func encoded(_ image: CIImage, look: PageLook) throws -> CGImage {
        let gray = look == .gray
        let space = gray ? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let pixels = context.createCGImage(image, from: image.extent, format: gray ? .L8 : .RGBA8, colorSpace: space) else {
            throw PDFWriterError.cannotEncodePage
        }
        let jpeg = try jpeg(pixels)
        guard gray, let levels = sixteenLevels(of: pixels, space: space), embeddedSize(of: levels) < embeddedSize(of: jpeg) else { return jpeg }
        return levels
    }

    /// The gray image with 4 bits per pixel, which the PDF stores as it is, compressed without loss.
    private func sixteenLevels(of pixels: CGImage, space: CGColorSpace) -> CGImage? {
        guard pixels.bitsPerPixel == 8, let data = pixels.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let width = pixels.width, height = pixels.height, sourceRow = pixels.bytesPerRow
        let row = (width + 1) / 2
        var packed = [UInt8](repeating: 0, count: row * height)
        for y in 0..<height {
            for x in 0..<width {
                let level = UInt8((Int(bytes[y * sourceRow + x]) * 15 + 127) / 255)
                packed[y * row + x / 2] |= x.isMultiple(of: 2) ? level << 4 : level
            }
        }
        guard let provider = CGDataProvider(data: Data(packed) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 4, bitsPerPixel: 4, bytesPerRow: row, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The size of a PDF with only this image, to compare two encodings of a page as the PDF stores them.
    private func embeddedSize(of image: CGImage) -> Int {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return .max }
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: box)
        pdf.endPDFPage()
        pdf.closePDF()
        return data.count
    }

    private func jpeg(_ pixels: CGImage) throws -> CGImage {
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
