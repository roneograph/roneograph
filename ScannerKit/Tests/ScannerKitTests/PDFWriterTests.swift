import CoreGraphics
import CoreImage
import Foundation
import ImageIO
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

    @Test func writesPagesOneAtATimeLikeAllAtOnce() throws {
        let writer = PDFWriter(context: context)
        let pages = [PDFPageContent(image: SyntheticPage().render(), look: .gray), PDFPageContent(image: SyntheticPage(stamp: true).render(), look: .color)]
        let document = try writer.document(title: "Invoice", defaultPaper: .a4)
        for page in pages {
            try document.add(page)
        }
        let streamed = document.close()
        let whole = try writer.data(pages: pages, title: "Invoice", defaultPaper: .a4)
        #expect(try #require(PDFDocument(data: streamed)).pageCount == 2)
        for number in 1...2 {
            #expect(try pixels(ofPage: number, of: streamed) == pixels(ofPage: number, of: whole))
        }
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

    @Test func writesAGrayPageOfTextInSixteenLosslessLevels() throws {
        let text = whitePaper(SyntheticPage().render())
        let levels = try PDFWriter(context: context).data(pages: [PDFPageContent(image: text, look: .gray)], title: "", defaultPaper: .a4)
        #expect(levels.range(of: Data("/BitsPerComponent 4".utf8)) != nil)
        #expect(levels.range(of: Data("/DCTDecode".utf8)) == nil)
    }

    @Test func writesAColorPageAndAGrayPictureAsJPEG() throws {
        let color = try PDFWriter(context: context).data(pages: [PDFPageContent(image: whitePaper(SyntheticPage().render()), look: .color)], title: "", defaultPaper: .a4)
        #expect(color.range(of: Data("/DCTDecode".utf8)) != nil)

        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.applyingGaussianBlur(sigma: 6).cropped(to: CGRect(x: 0, y: 0, width: 1240, height: 1754))
        let picture = try PDFWriter(context: context).data(pages: [PDFPageContent(image: noise, look: .gray)], title: "", defaultPaper: .a4)
        #expect(picture.range(of: Data("/DCTDecode".utf8)) != nil)
        #expect(picture.range(of: Data("/BitsPerComponent 4".utf8)) == nil)
    }

    @Test func keepsAFaintMarkOnAGrayPageOfText() throws {
        let faint: UInt8 = 230
        let width = 620, height = 877
        var gray = [UInt8](repeating: 255, count: width * height)
        for y in 400..<440 { for x in 100..<520 { gray[y * width + x] = faint } }
        for y in stride(from: 100, to: 300, by: 20) { for x in 100..<520 { gray[y * width + x] = 0 } }
        let space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
        let bitmap = try #require(CGContext(data: &gray, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let page = CIImage(cgImage: try #require(bitmap.makeImage()))
        let data = try PDFWriter(context: context).data(pages: [PDFPageContent(image: page, look: .gray)], title: "", defaultPaper: .a4)
        #expect(data.range(of: Data("/BitsPerComponent 4".utf8)) != nil)

        let rendered = try pixels(ofFirstPageOf: data)
        let size = Paper.a4.size
        let mark = rendered[Int(size.height) * 420 / height * Int(size.width) + Int(size.width) / 2]
        #expect(abs(Int(mark) - Int(faint)) <= 9)
        #expect(rendered[Int(size.height) * 700 / height * Int(size.width) + Int(size.width) / 2] == 255)
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

    @Test(arguments: [(PageLook.gray, 1.0), (.gray, 2.0), (.color, 1.0), (.color, 2.0)])
    func keepsTheEdgesOfAWhitePageWhite(look: PageLook, scale: CGFloat) throws {
        let white = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 840 * scale, height: 1188 * scale))
        let data = try PDFWriter(context: context).data(pages: [PDFPageContent(image: white, look: look)], title: "", defaultPaper: .a4)
        let (pixels, width, height) = try grayImage(onFirstPageOf: data)
        #expect(width == (scale == 1 ? 840 : 1240))
        let edges = edgePixels(of: pixels, width: width, height: height)
        #expect(edges.allSatisfy { $0 == 255 }, "darkest edge pixel \(edges.min() ?? 0)")
    }

    @Test func keepsTheTextInvisible() throws {
        let image = SyntheticPage().render()
        let line = TextLine(text: "Invoice 2026-114 Lumen Energy", frame: CGRect(x: 0.1, y: 0.02, width: 0.5, height: 0.03))
        let writer = PDFWriter(context: context)
        let withText = try writer.data(pages: [PDFPageContent(image: image, look: .gray, text: [line])], title: "", defaultPaper: .a4)
        let withoutText = try writer.data(pages: [PDFPageContent(image: image, look: .gray)], title: "", defaultPaper: .a4)
        #expect(try pixels(ofFirstPageOf: withText) == pixels(ofFirstPageOf: withoutText))
    }

    /// The image of the first page in 8-bit gray, row 0 at the top.
    private func grayImage(onFirstPageOf data: Data) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        defer { withExtendedLifetime(document) {} }
        let page = try #require(document.page(at: 1)?.dictionary)
        var resources: CGPDFDictionaryRef?, images: CGPDFDictionaryRef?
        #expect(CGPDFDictionaryGetDictionary(page, "Resources", &resources))
        #expect(resources.map { CGPDFDictionaryGetDictionary($0, "XObject", &images) } == true)
        var stream: CGPDFStreamRef?
        CGPDFDictionaryApplyBlock(try #require(images), { _, object, _ in
            CGPDFObjectGetValue(object, .stream, &stream)
            return stream == nil
        }, nil)
        let image = try #require(stream)
        var format = CGPDFDataFormat.raw, width: CGPDFInteger = 0, height: CGPDFInteger = 0
        let bytes = try #require(CGPDFStreamCopyData(image, &format)) as Data
        let dictionary = try #require(CGPDFStreamGetDictionary(image))
        #expect(CGPDFDictionaryGetInteger(dictionary, "Width", &width) && CGPDFDictionaryGetInteger(dictionary, "Height", &height))
        var pixels = [UInt8](repeating: 0, count: width * height)
        if format == .raw {
            let packed = [UInt8](bytes), row = (width + 1) / 2
            for y in 0..<height {
                for x in 0..<width {
                    let byte = packed[y * row + x / 2]
                    pixels[y * width + x] = (x.isMultiple(of: 2) ? byte >> 4 : byte & 15) * 17
                }
            }
        } else {
            let decoded = try #require(CGImageSourceCreateWithData(bytes as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
            let bitmap = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
            bitmap.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (pixels, width, height)
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

    /// The page as the cleanup leaves it: white where the paper is.
    private func whitePaper(_ page: CIImage) -> CIImage {
        PageCleaner(context: context).render(page, analysis: .sample, look: .gray)
    }

    private func pixels(ofFirstPageOf data: Data) throws -> [UInt8] {
        try pixels(ofPage: 1, of: data)
    }

    private func pixels(ofPage number: Int, of data: Data) throws -> [UInt8] {
        let page = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!)?.page(at: number))
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width), height = Int(box.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let bitmap = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        bitmap.drawPDFPage(page)
        return pixels
    }
}
