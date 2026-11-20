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

    /// `details` go into the metadata: the issuer as the author, the document type, issuer and number as keywords, and the document date as the creation date.
    public func data(pages: [PDFPageContent], title: String, subject: String? = nil, details: DocumentDetails = DocumentDetails(), defaultPaper: Paper) throws -> Data {
        let document = try document(title: title, subject: subject, details: details, defaultPaper: defaultPaper)
        for page in pages {
            try document.add(page)
        }
        return document.close()
    }

    /// A PDF written one page at a time, so the image of a page can be released once it is added.
    public func document(title: String, subject: String? = nil, details: DocumentDetails = DocumentDetails(), defaultPaper: Paper) throws -> Document {
        try Document(writer: self, title: title, subject: subject, details: details, defaultPaper: defaultPaper)
    }

    public final class Document {
        private let writer: PDFWriter
        private let defaultPaper: Paper
        private let data = NSMutableData()
        private let pdf: CGContext
        /// One font for the whole document: the PDF embeds a font subset for each font object it is given, and Core Text does not always hand back the same object for each size.
        private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        private let created: Date?

        fileprivate init(writer: PDFWriter, title: String, subject: String?, details: DocumentDetails, defaultPaper: Paper) throws {
            self.writer = writer
            self.defaultPaper = defaultPaper
            created = details.date
            var info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: writer.creator, kCGPDFContextCreatePDFA: true]
            if let subject { info[kCGPDFContextSubject] = subject }
            if let issuer = details.issuer { info[kCGPDFContextAuthor] = issuer }
            let keywords = [details.documentType == .other ? nil : details.documentType.rawValue, details.issuer, details.number].compactMap(\.self)
            if !keywords.isEmpty { info[kCGPDFContextKeywords] = keywords }
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let pdf = CGContext(consumer: consumer, mediaBox: nil, info as CFDictionary) else {
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
            writer.drawInvisibly(page.text, in: pdf, font: font, pageSize: box.size)
            pdf.endPDFPage()
        }

        public func close() -> Data {
            pdf.closePDF()
            guard let created else { return data as Data }
            return PDFCreationDate.setting(created, in: data as Data)
        }
    }

    /// Stretches each line over the box where it was read, so a selection covers the printed words.
    private func drawInvisibly(_ lines: [TextLine], in pdf: CGContext, font: CTFont, pageSize: CGSize) {
        pdf.saveGState()
        pdf.setTextDrawingMode(.invisible)
        for line in lines where !line.text.isEmpty {
            let frame = CGRect(x: line.frame.minX * pageSize.width, y: (1 - line.frame.maxY) * pageSize.height, width: line.frame.width * pageSize.width, height: line.frame.height * pageSize.height)
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

/// Core Graphics dates a PDF when it is written and has no option for another creation date, so the date is changed by an incremental update:
/// new versions of the document information and of the XMP metadata appended to the file, which PDF/A allows. The file is kept as is when it is not laid out as expected.
enum PDFCreationDate {
    static func setting(_ date: Date, in pdf: Data, timeZone: TimeZone = .current) -> Data {
        guard let trailerStart = pdf.lastRange(of: "trailer"), let startxref = pdf.lastRange(of: "startxref") else { return pdf }
        let trailer = pdf.text(trailerStart.upperBound..<startxref.lowerBound)
        guard let size = trailer.firstNumber(after: "/Size "), let root = trailer.firstNumber(after: "/Root "), let info = trailer.firstNumber(after: "/Info "),
              let previous = pdf.text(startxref.upperBound..<pdf.endIndex).firstNumber(after: ""),
              let id = trailer.range(of: "/ID").map({ String(trailer[$0.lowerBound...]).prefix(while: { $0 != "]" }) + "]" }),
              let catalog = pdf.object(root), let metadata = pdf.text(catalog).firstNumber(after: "/Metadata "),
              let infoObject = pdf.object(info), let xmp = pdf.stream(of: metadata) else { return pdf }

        let xmpText = xmp.replacingOccurrences(of: #"<xmp:CreateDate>[^<]*</xmp:CreateDate>"#, with: "<xmp:CreateDate>\(xmpDate(date, timeZone))</xmp:CreateDate>", options: .regularExpression)
        guard xmpText.contains("<xmp:CreateDate>"), let creation = pdf.range(of: Data("/CreationDate (".utf8), in: infoObject),
              let end = pdf.range(of: Data(")".utf8), in: creation.upperBound..<infoObject.upperBound) else { return pdf }
        // Strings outside ASCII are written as UTF-16, so the information is changed as bytes.
        var infoData = Data(pdf[infoObject])
        infoData.replaceSubrange((creation.upperBound - infoObject.lowerBound)..<(end.lowerBound - infoObject.lowerBound), with: Data(infoDate(date, timeZone).utf8))

        var updated = pdf
        if updated.last != UInt8(ascii: "\n") { updated.append(Data("\n".utf8)) }
        let xmpData = Data(xmpText.utf8)
        let metadataOffset = updated.count
        updated.append(Data("\(metadata) 0 obj\n<< /Type /Metadata /Subtype /XML /Length \(xmpData.count) >>\nstream\n".utf8) + xmpData + Data("\nendstream\nendobj\n".utf8))
        let infoOffset = updated.count
        updated.append(Data("\(info) 0 obj".utf8) + infoData + Data("endobj\n".utf8))
        let xref = updated.count
        let entries = [(metadata, metadataOffset), (info, infoOffset)].sorted { $0.0 < $1.0 }
            .map { String(format: "%d 1\n%010d 00000 n \n", $0.0, $0.1) }.joined()
        updated.append(Data("xref\n\(entries)trailer\n<< /Size \(size) /Root \(root) 0 R /Info \(info) 0 R /Prev \(previous) \(id) >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return updated
    }

    /// `D:20261012120000+02'00'`
    static func infoDate(_ date: Date, _ timeZone: TimeZone) -> String {
        let (c, sign, hours, minutes) = parts(date, timeZone)
        return String(format: "D:%04d%02d%02d%02d%02d%02d%@%02d'%02d'", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, sign, hours, minutes)
    }

    /// `2026-10-12T12:00:00+02:00`
    static func xmpDate(_ date: Date, _ timeZone: TimeZone) -> String {
        let (c, sign, hours, minutes) = parts(date, timeZone)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d%@%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, sign, hours, minutes)
    }

    private static func parts(_ date: Date, _ timeZone: TimeZone) -> (DateComponents, String, Int, Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let offset = timeZone.secondsFromGMT(for: date)
        return (calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date), offset < 0 ? "-" : "+", abs(offset) / 3600, abs(offset) % 3600 / 60)
    }
}

private extension Data {
    func lastRange(of text: String) -> Range<Index>? {
        range(of: Data(text.utf8), options: .backwards)
    }

    func text(_ range: Range<Index>) -> String {
        String(decoding: self[range], as: UTF8.self)
    }

    /// The bytes between `N 0 obj` and `endobj` of the last version of an object.
    func object(_ number: Int) -> Range<Index>? {
        guard let start = lastRange(of: "\n\(number) 0 obj"), let end = range(of: Data("endobj".utf8), in: start.upperBound..<endIndex) else { return nil }
        return start.upperBound..<end.lowerBound
    }

    /// The decoded text of a stream object, plain or Flate-compressed.
    func stream(of number: Int) -> String? {
        guard let object = object(number), let start = range(of: Data("stream".utf8), in: object) else { return nil }
        let dictionary = text(object.lowerBound..<start.lowerBound)
        guard let length = dictionary.firstNumber(after: "/Length ") else { return nil }
        var bodyStart = start.upperBound
        if self[bodyStart] == UInt8(ascii: "\r") { bodyStart += 1 }
        if self[bodyStart] == UInt8(ascii: "\n") { bodyStart += 1 }
        guard bodyStart + length <= object.upperBound else { return nil }
        let body = self[bodyStart..<(bodyStart + length)]
        guard dictionary.contains("/FlateDecode") else { return String(decoding: body, as: UTF8.self) }
        guard body.count > 6, let inflated = try? (Data(body.dropFirst(2).dropLast(4)) as NSData).decompressed(using: .zlib) else { return nil }
        return String(decoding: inflated as Data, as: UTF8.self)
    }
}

private extension String {
    /// The integer right after `prefix`.
    func firstNumber(after prefix: String) -> Int? {
        let start = prefix.isEmpty ? startIndex : range(of: prefix)?.upperBound
        guard let start else { return nil }
        return Int(self[start...].drop(while: \.isWhitespace).prefix(while: \.isNumber))
    }
}
