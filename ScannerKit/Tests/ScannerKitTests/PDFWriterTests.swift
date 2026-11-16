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

    @Test func neverUpscalesASmallImage() throws {
        let tiny = SyntheticPage().render().transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        let data = try PDFWriter(context: context).data(pages: [PDFPageContent(image: tiny, look: .gray)], title: "", defaultPaper: .a4)
        #expect(data.range(of: Data("/Width 210".utf8)) != nil)
    }
}
