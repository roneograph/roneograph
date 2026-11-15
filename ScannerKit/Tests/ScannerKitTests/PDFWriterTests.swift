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
        let data = try PDFWriter(context: context).data(pages: [PDFPageContent(image: page, look: .gray), PDFPageContent(image: page, look: .blackAndWhite)], title: "Invoice", quality: .balanced, defaultPaper: .a4)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2)
        let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(box.width - Paper.a4.size.width) < 1 && abs(box.height - Paper.a4.size.height) < 1)
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Invoice")
        #expect(document.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String == "Roneograph")
    }

    @Test func embedsJPEGForGrayAnd1BitForBlackAndWhite() throws {
        let page = SyntheticPage().render()
        let writer = PDFWriter(context: context)
        let gray = try writer.data(pages: [PDFPageContent(image: page, look: .gray)], title: "", quality: .balanced, defaultPaper: .a4)
        let bw = try writer.data(pages: [PDFPageContent(image: page, look: .blackAndWhite)], title: "", quality: .balanced, defaultPaper: .a4)
        #expect(gray.range(of: Data("/DCTDecode".utf8)) != nil)
        #expect(bw.range(of: Data("/DCTDecode".utf8)) == nil)
        #expect(bw.range(of: Data("/BitsPerComponent 1".utf8)) != nil)
    }

    @Test func smallerQualityMakesSmallerFiles() throws {
        let page = SyntheticPage(stamp: true, shadow: true).render()
        let writer = PDFWriter(context: context)
        let sizes = try PDFQuality.allCases.map { try writer.data(pages: [PDFPageContent(image: page, look: .color)], title: "", quality: $0, defaultPaper: .a4).count }
        #expect(sizes == sizes.sorted())
        #expect(sizes[0] < sizes[2])
    }

    @Test func neverUpscalesASmallImage() throws {
        let tiny = SyntheticPage().render().transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        let data = try PDFWriter(context: context).data(pages: [PDFPageContent(image: tiny, look: .gray)], title: "", quality: .best, defaultPaper: .a4)
        #expect(data.range(of: Data("/Width 210".utf8)) != nil)
    }
}
