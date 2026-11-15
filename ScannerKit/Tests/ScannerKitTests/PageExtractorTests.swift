import CoreGraphics
import CoreImage
import ScannerKit
import Testing

struct PageExtractorTests {
    let extractor = PageExtractor(context: CIContext())
    let tilted = Quad(topLeft: CGPoint(x: 0.22, y: 0.18), topRight: CGPoint(x: 0.8, y: 0.21), bottomRight: CGPoint(x: 0.86, y: 0.82), bottomLeft: CGPoint(x: 0.14, y: 0.8))

    @Test func findsATiltedPage() throws {
        let photo = SyntheticPhoto.render(page: tilted)
        let detection = try #require(extractor.detect(in: photo))
        #expect(detection.quad.maxCornerDistance(to: tilted) < 0.02)
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

/// A 1200 × 1600 photo of a page with text lines on a dark desk.
enum SyntheticPhoto {
    static let size = CGSize(width: 1200, height: 1600)

    static func render(page: Quad?, contentAtTop: Bool = true, paper: CGFloat = 0.97) -> CIImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(red: 0.32, green: 0.24, blue: 0.17, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        if let page {
            let corners = page.scaled(to: size)
            context.setFillColor(red: paper, green: paper, blue: paper * 0.97, alpha: 1)
            context.addLines(between: corners)
            context.closePath()
            context.fillPath()

            func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                let top = CGPoint(x: corners[0].x + (corners[1].x - corners[0].x) * u, y: corners[0].y + (corners[1].y - corners[0].y) * u)
                let bottom = CGPoint(x: corners[3].x + (corners[2].x - corners[3].x) * u, y: corners[3].y + (corners[2].y - corners[3].y) * u)
                return CGPoint(x: top.x + (bottom.x - top.x) * v, y: top.y + (bottom.y - top.y) * v)
            }
            context.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            let start: CGFloat = contentAtTop ? 0.08 : 0.55
            for line in 0..<14 {
                let v = start + CGFloat(line) * 0.026
                let end: CGFloat = line % 5 == 4 ? 0.5 : 0.9
                context.addLines(between: [at(0.1, v), at(end, v), at(end, v + 0.012), at(0.1, v + 0.012)])
                context.closePath()
            }
            context.fillPath()
        }
        return CIImage(cgImage: context.makeImage()!)
    }
}
