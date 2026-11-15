import CoreGraphics
import CoreImage
import Foundation
import PDFKit
import ScannerKit
import Testing

struct PageSizingTests {
    let sizing = PageSizing()

    @Test func snapsToA4() {
        #expect(sizing.pageSize(forImage: CGSize(width: 1704, height: 2471), defaultPaper: .letter) == Paper.a4.size)
    }

    @Test func snapsToLetter() {
        #expect(sizing.pageSize(forImage: CGSize(width: 1700, height: 2210), defaultPaper: .a4) == Paper.letter.size)
    }

    @Test func usesTheDefaultPaperHalfwayBetweenA4AndLetter() {
        let halfway = CGSize(width: 1000, height: 1350)
        #expect(sizing.pageSize(forImage: halfway, defaultPaper: .a4) == Paper.a4.size)
        #expect(sizing.pageSize(forImage: halfway, defaultPaper: .letter) == Paper.letter.size)
    }

    @Test func keepsTheProportionsOfOtherShapesInsideTheDefaultPaper() {
        let receipt = sizing.pageSize(forImage: CGSize(width: 800, height: 2400), defaultPaper: .a4)
        #expect(abs(receipt.height - Paper.a4.size.height) < 0.01)
        #expect(abs(receipt.width - Paper.a4.size.height / 3) < 0.01)
    }

    @Test func keepsLandscapePagesLandscape() {
        #expect(sizing.pageSize(forImage: CGSize(width: 2471, height: 1704), defaultPaper: .a4) == CGSize(width: Paper.a4.size.height, height: Paper.a4.size.width))
    }
}

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
