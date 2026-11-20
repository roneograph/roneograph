import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import ScannerKit
import ScannerKitTesting
import Testing

@Suite(.serialized)
struct PageCleanerTests {
    let context = CIContext()
    var cleaner: PageCleaner { PageCleaner(context: context) }

    @Test func suggestsGrayForTextEvenOnTintedPaper() async throws {
        for page in [SyntheticPage(), SyntheticPage(shadedHeader: true), SyntheticPage(paper: (0.86, 0.8, 0.62))] {
            let analysis = try await cleaner.analyze(page.render())
            #expect(analysis.suggestedLook == .gray)
            #expect(analysis.orientation == .up)
        }
    }

    @Test func measuresTheTextLineHeight() async throws {
        let height = try #require(try await cleaner.analyze(SyntheticPage().render()).textLineHeight)
        #expect((0.012...0.018).contains(height))
    }

    @Test(arguments: [4, 6])
    func measuresTheTextLineHeightOnlyWithEnoughLines(lines: Int) async throws {
        let height = try await cleaner.analyze(SyntheticPage(lines: lines).render()).textLineHeight
        #expect((height == nil) == (lines < 5))
    }

    @Test func takesAPageWhoseTextCannotBeReadForUpright() async throws {
        struct Failure: Error {}
        let cleaner = PageCleaner(context: context) { _ in throw Failure() }
        let analysis = try await cleaner.analyze(SyntheticPage(stamp: true).render().oriented(.down))
        #expect(analysis.orientation == .up)
        #expect(analysis.textLineHeight == nil)
        #expect(analysis.suggestedLook == .color)
    }

    @Test func stopsWhenCancelled() async {
        let cleaner = cleaner, page = SyntheticPage().render()
        await #expect(throws: (any Error).self) { try await inCancelledTask { try await cleaner.analyze(page) } }
        await #expect(throws: CancellationError.self) { try await PageCleaner(context: context) { _ in throw CancellationError() }.analyze(page) }
    }

    @Test func aColoredStampKeepsColor() async throws {
        #expect(try await cleaner.analyze(SyntheticPage(stamp: true).render()).suggestedLook == .color)
    }

    @Test func aLargePictureStaysDark() async throws {
        let page = SyntheticPage(picture: true).render()
        let analysis = try await cleaner.analyze(page)
        let (r, _, _) = color(of: cleaner.render(page, analysis: analysis, look: analysis.suggestedLook), at: CGPoint(x: 0.5, y: 0.55))
        #expect(r < 0.4)
    }

    @Test(arguments: [(CGImagePropertyOrientation.down, PageOrientation.down), (.right, .left), (.left, .right)])
    func turnsAPageUpright(turned: CGImagePropertyOrientation, fix: PageOrientation) async throws {
        #expect(try await cleaner.analyze(SyntheticPage().render().oriented(turned)).orientation == fix)
    }

    @Test(arguments: [3.0, -2.0])
    func measuresAndRemovesTheSkew(degrees: Double) async throws {
        let page = SyntheticPage(rotation: degrees).render()
        let analysis = try await cleaner.analyze(page)
        #expect(abs(analysis.skewDegrees - degrees) < 0.3)

        let straight = cleaner.render(page, analysis: analysis, look: .gray)
        #expect(abs(try await cleaner.analyze(straight).skewDegrees) < 0.3)
    }

    @Test func keepsTheCornersOfATallPageItStraightens() throws {
        let size = CGSize(width: 300, height: 1200), mark: CGFloat = 30, inset: CGFloat = 12
        var page = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 0.93)).cropped(to: CGRect(origin: .zero, size: size))
        for corner in [CGPoint(x: inset, y: inset), CGPoint(x: size.width - inset - mark, y: inset), CGPoint(x: inset, y: size.height - inset - mark), CGPoint(x: size.width - inset - mark, y: size.height - inset - mark)] {
            page = CIImage(color: CIColor(red: 0.05, green: 0.05, blue: 0.05)).cropped(to: CGRect(origin: corner, size: CGSize(width: mark, height: mark))).composited(over: page)
        }
        var analysis = PageAnalysis.sample
        analysis.skewDegrees = 3

        let straight = cleaner.render(page, analysis: analysis, look: .gray)
        let width = Int(straight.extent.width), height = Int(straight.extent.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        context.render(straight, toBitmap: &pixels, rowBytes: width, bounds: straight.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        let ink = pixels.filter { $0 < 128 }.count
        #expect(abs(Double(ink) / Double(4 * mark * mark) - 1) < 0.1, "\(ink) dark pixels")
        let corners = [0, width - 1, (height - 1) * width, height * width - 1].map { pixels[$0] }
        #expect(corners.allSatisfy { $0 == 255 }, "corners \(corners)")
    }

    @Test func measuresTheSkewOfAPageWithADarkStripAlongASide() async throws {
        let page = SyntheticPage(rotation: 3).render()
        let strip = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: CGRect(x: 0, y: page.extent.height * 0.99, width: page.extent.width, height: page.extent.height * 0.01))
        #expect(abs(try await cleaner.analyze(strip.composited(over: page)).skewDegrees - 3) < 0.3)
    }

    @Test func evensOutAShadowAndWhitensYellowPaper() async throws {
        let page = SyntheticPage(paper: (0.86, 0.8, 0.62), shadow: true).render()
        let clean = cleaner.render(page, analysis: try await cleaner.analyze(page), look: .color)
        for point in [CGPoint(x: 0.05, y: 0.5), CGPoint(x: 0.95, y: 0.5), CGPoint(x: 0.5, y: 0.97)] {
            let (r, g, b) = color(of: clean, at: point)
            #expect(min(r, g, b) > 0.93, "paper at \(point) is \(r), \(g), \(b)")
        }
    }

    @Test func removesASharpEdgedShadowWithoutAGhost() async throws {
        let page = SyntheticPage(handShadow: true).render()
        let clean = cleaner.render(page, analysis: try await cleaner.analyze(page), look: .gray)
        for x in stride(from: 0.30, through: 0.70, by: 0.02) {
            let (r, _, _) = color(of: clean, at: CGPoint(x: x, y: 0.07))
            #expect(r > 0.97, "paper at \(x) is \(r)")
        }
    }

    @Test func whitensWhatTouchesTheSideOfThePageButKeepsWhatReachesIn() async throws {
        let page = SyntheticPage().render()
        let width = page.extent.width, height = page.extent.height
        let sliver = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: CGRect(x: 0, y: height * 0.7, width: width * 0.015, height: height * 0.2))
        let band = CIImage(color: CIColor(red: 0.15, green: 0.15, blue: 0.15)).cropped(to: CGRect(x: width * 0.985, y: height * 0.3, width: width * 0.015, height: height * 0.4))
            .composited(over: CIImage(color: CIColor(red: 0.15, green: 0.15, blue: 0.15)).cropped(to: CGRect(x: width * 0.85, y: height * 0.45, width: width * 0.15, height: height * 0.02)))
        let photo = sliver.composited(over: band).composited(over: page)
        let clean = cleaner.render(photo, analysis: try await cleaner.analyze(photo), look: .gray)
        #expect(color(of: clean, at: CGPoint(x: 0.007, y: 0.2)).0 > 0.95)
        #expect(color(of: clean, at: CGPoint(x: 0.993, y: 0.5)).0 < 0.4)
        #expect(color(of: clean, at: CGPoint(x: 0.9, y: 0.54)).0 < 0.4)
    }

    @Test func keepsTheInkBlack() async throws {
        let page = SyntheticPage(paper: (0.86, 0.8, 0.62), shadow: true).render()
        let clean = cleaner.render(page, analysis: try await cleaner.analyze(page), look: .gray)
        let (r, _, _) = color(of: clean, at: SyntheticPage.blockCenter)
        #expect(r < 0.2)
    }

    /// sRGB color at a normalized point, origin at the top left.
    private func color(of image: CIImage, at point: CGPoint) -> (Double, Double, Double) {
        let x = image.extent.minX + point.x * image.extent.width
        let y = image.extent.maxY - point.y * image.extent.height
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x.rounded(.down), y: y.rounded(.down) - 1, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }
}
