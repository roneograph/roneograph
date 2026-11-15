import CoreGraphics
import CoreImage
import ScannerKit
import ScannerKitTesting
import Testing

struct PageExtractorTests {
    let extractor = PageExtractor(context: CIContext())
    let tilted = Quad(topLeft: CGPoint(x: 0.22, y: 0.18), topRight: CGPoint(x: 0.8, y: 0.21), bottomRight: CGPoint(x: 0.86, y: 0.82), bottomLeft: CGPoint(x: 0.14, y: 0.8))

    @Test func findsATiltedPage() throws {
        let photo = SyntheticPhoto.render(page: tilted)
        let quad = try #require(extractor.detect(in: photo))
        #expect(quad.maxCornerDistance(to: tilted) < 0.02)
    }

    @Test func findsNothingWithoutAPage() {
        let photo = SyntheticPhoto.render(page: nil)
        #expect(extractor.detect(in: photo) == nil)
    }

    @Test func correctionKeepsTheProportionsOfAFlatPage() {
        let a4 = Quad.rect(x: 0.2, y: 0.1, width: 0.6, height: 0.6 * 1.4142 * 1200 / 1600)
        let page = extractor.correct(SyntheticPhoto.render(page: a4), quad: a4)
        #expect(page.extent.origin == .zero)
        #expect(abs(page.extent.height / page.extent.width - 1.4142) < 0.01)
    }

    @Test func signatureIgnoresExposureButNotContent() throws {
        let photo = SyntheticPhoto.render(page: tilted, contentAtTop: true)
        let darker = SyntheticPhoto.render(page: tilted, contentAtTop: true, paper: 0.8)
        let other = SyntheticPhoto.render(page: tilted, contentAtTop: false)
        let reference = try #require(extractor.signature(of: photo, quad: tilted))
        #expect(try #require(extractor.signature(of: darker, quad: tilted)).distance(to: reference) < 0.03)
        #expect(try #require(extractor.signature(of: other, quad: tilted)).distance(to: reference) > CaptureTrigger.Configuration().rearmContentDistance)
    }

    @Test func encodesJPEG() throws {
        let data = try #require(extractor.jpegData(of: SyntheticPhoto.render(page: tilted), quality: 0.8))
        #expect(data.starts(with: [0xFF, 0xD8]))
    }
}
