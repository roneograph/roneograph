import CoreGraphics
import CoreImage
import Foundation
import PDFKit
import ScannerKit
import ScannerKitTesting
import Testing

struct PDFWriterTests {
    let context = CIContext()

    @Test func writesOnePagePerImageAtTheRightSize() throws {
        let page = SyntheticPage().render()
        let data = try PDFWriter(context: context).data(pages: [PDFPageContent(image: page, look: .gray), PDFPageContent(image: page, look: .color)], title: "Invoice", defaultPaper: .a4)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2)
        let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - Paper.a4.size.width) < 1 && abs(box.height - Paper.a4.size.height) < 1)
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Invoice")
        #expect(document.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String == "Roneograph")
    }

    @Test func declaresPDFAWithAnOutputIntent() throws {
        let data = try PDFWriter(context: context).data(pages: [PDFPageContent(image: SyntheticPage().render(), look: .color)], title: "Invoice", defaultPaper: .a4)
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        let catalog = try #require(document.catalog)

        var metadata: CGPDFStreamRef?
        #expect(CGPDFDictionaryGetStream(catalog, "Metadata", &metadata))
        var format = CGPDFDataFormat.raw
        let xmp = try #require(metadata.flatMap { CGPDFStreamCopyData($0, &format) }.map { String(decoding: $0 as Data, as: UTF8.self) })
        #expect(xmp.contains("<pdfaid:part>2</pdfaid:part>"))
        #expect(xmp.contains("<pdfaid:conformance>B</pdfaid:conformance>"))

        var intents: CGPDFArrayRef?, intent: CGPDFDictionaryRef?, subtype: UnsafePointer<CChar>?
        #expect(CGPDFDictionaryGetArray(catalog, "OutputIntents", &intents))
        #expect(intents.map { CGPDFArrayGetDictionary($0, 0, &intent) } == true)
        #expect(intent.map { CGPDFDictionaryGetName($0, "S", &subtype) } == true)
        #expect(subtype.map { String(cString: $0) } == "GTS_PDFA1")
    }

    @Test func embedsPagesAsJPEG() throws {
        let gray = try PDFWriter(context: context).data(pages: [PDFPageContent(image: SyntheticPage().render(), look: .gray)], title: "", defaultPaper: .a4)
        #expect(gray.range(of: Data("/DCTDecode".utf8)) != nil)
    }

    @Test(arguments: [(PageLook.gray, 1), (.color, 3)])
    func writesEachLookWithItsColorComponents(look: PageLook, components: Int) throws {
        let data = try PDFWriter(context: context).data(pages: [PDFPageContent(image: SyntheticPage().render(), look: look)], title: "", defaultPaper: .a4)
        #expect(try componentCount(ofImageOnFirstPageOf: data) == components)
    }

    @Test func neverUpscalesASmallImage() throws {
        let tiny = SyntheticPage().render().transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        let data = try PDFWriter(context: context).data(pages: [PDFPageContent(image: tiny, look: .gray)], title: "", defaultPaper: .a4)
        #expect(data.range(of: Data("/Width 210".utf8)) != nil)
    }

    @Test func makesTheTextSearchableOverTheWordsItWasReadFrom() throws {
        let line = TextLine(text: "Invoice 2026-114 Lumen Energy", frame: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.02))
        let data = try PDFWriter(context: context).data(pages: [PDFPageContent(image: SyntheticPage().render(), look: .gray, text: [line])], title: "", defaultPaper: .a4)
        let document = try #require(PDFDocument(data: data))
        #expect(document.page(at: 0)?.string?.contains("Invoice 2026-114 Lumen Energy") == true)

        let found = try #require(document.findString("Invoice 2026-114 Lumen Energy", withOptions: []).first)
        let bounds = found.bounds(for: try #require(document.page(at: 0)))
        let size = Paper.a4.size
        let expected = CGRect(x: 0.1 * size.width, y: 0.78 * size.height, width: 0.5 * size.width, height: 0.02 * size.height)
        #expect(abs(bounds.minX - expected.minX) < 2 && abs(bounds.maxX - expected.maxX) < 2)
        #expect(abs(bounds.midY - expected.midY) < expected.height / 2)
    }

    @Test func keepsTheTextInvisible() throws {
        let image = SyntheticPage().render()
        let line = TextLine(text: "Invoice 2026-114 Lumen Energy", frame: CGRect(x: 0.1, y: 0.02, width: 0.5, height: 0.03))
        let writer = PDFWriter(context: context)
        let withText = try writer.data(pages: [PDFPageContent(image: image, look: .gray, text: [line])], title: "", defaultPaper: .a4)
        let withoutText = try writer.data(pages: [PDFPageContent(image: image, look: .gray)], title: "", defaultPaper: .a4)
        #expect(try pixels(ofFirstPageOf: withText) == pixels(ofFirstPageOf: withoutText))
    }

    /// Components of the ICC profile of the image on the first page.
    private func componentCount(ofImageOnFirstPageOf data: Data) throws -> Int? {
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        defer { withExtendedLifetime(document) {} }
        let page = try #require(document.page(at: 1)?.dictionary)
        var resources: CGPDFDictionaryRef?, images: CGPDFDictionaryRef?
        #expect(CGPDFDictionaryGetDictionary(page, "Resources", &resources))
        #expect(resources.map { CGPDFDictionaryGetDictionary($0, "XObject", &images) } == true)
        var colorSpace: CGPDFObjectRef?
        CGPDFDictionaryApplyBlock(try #require(images), { _, object, _ in
            var image: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .stream, &image), let image, let dictionary = CGPDFStreamGetDictionary(image) {
                CGPDFDictionaryGetObject(dictionary, "ColorSpace", &colorSpace)
            }
            return colorSpace == nil
        }, nil)

        var array: CGPDFArrayRef?, profile: CGPDFStreamRef?, count: CGPDFInteger = 0
        guard CGPDFObjectGetValue(try #require(colorSpace), .array, &array), let array,
              CGPDFArrayGetStream(array, 1, &profile), let profile,
              CGPDFDictionaryGetInteger(try #require(CGPDFStreamGetDictionary(profile)), "N", &count) else { return nil }
        return count
    }

    private func pixels(ofFirstPageOf data: Data) throws -> [UInt8] {
        let page = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!)?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width), height = Int(box.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let bitmap = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        bitmap.drawPDFPage(page)
        return pixels
    }
}
