import CoreGraphics
import CoreImage
import CoreText
import ImageIO
import ScannerKit
import ScannerKitTesting
import Testing

@Suite(.serialized)
struct PageCleanerTests {
    let context = CIContext()
    var cleaner: PageCleaner { PageCleaner(context: context) }

    @Test func textIsGrayNeverBlackAndWhite() {
        for page in [SyntheticPage(), SyntheticPage(shadedHeader: true)] {
            let analysis = cleaner.analyze(page.render())
            #expect(analysis.suggestedLook == .gray)
            #expect(analysis.orientation == .up)
        }
    }

    @Test func aColoredStampKeepsColor() {
        #expect(cleaner.analyze(SyntheticPage(stamp: true).render()).suggestedLook == .color)
    }

    @Test func aLargePictureIsAPhoto() {
        #expect(cleaner.analyze(SyntheticPage(picture: true).render()).suggestedLook == .photo)
    }

    @Test func turnsAnUpsideDownPageUpright() {
        let page = SyntheticPage().render().oriented(.down)
        #expect(cleaner.analyze(page).orientation == .down)
    }

    @Test(arguments: [(CGImagePropertyOrientation.right, PageOrientation.left), (.left, .right)])
    func turnsASidewaysPageUpright(turned: CGImagePropertyOrientation, fix: PageOrientation) {
        #expect(cleaner.analyze(SyntheticPage().render().oriented(turned)).orientation == fix)
    }

    @Test(arguments: [3.0, -2.0])
    func measuresAndRemovesTheSkew(degrees: Double) {
        let page = SyntheticPage(rotation: degrees).render()
        let analysis = cleaner.analyze(page)
        #expect(abs(analysis.skewDegrees - degrees) < 0.3)

        let straight = cleaner.render(page, analysis: analysis, settings: CleanupSettings(look: .gray))
        #expect(abs(cleaner.analyze(straight).skewDegrees) < 0.3)
    }

    @Test func evensOutAShadowAndWhitensYellowPaper() {
        let page = SyntheticPage(paper: (0.86, 0.8, 0.62), shadow: true).render()
        let clean = cleaner.render(page, analysis: cleaner.analyze(page), settings: CleanupSettings(look: .color))
        for point in [CGPoint(x: 0.05, y: 0.5), CGPoint(x: 0.95, y: 0.5), CGPoint(x: 0.5, y: 0.97)] {
            let (r, g, b) = color(of: clean, at: point)
            #expect(min(r, g, b) > 0.93, "paper at \(point) is \(r), \(g), \(b)")
        }
    }

    @Test func removesASharpEdgedShadowWithoutAGhost() {
        let page = SyntheticPage(handShadow: true).render()
        let clean = cleaner.render(page, analysis: cleaner.analyze(page), settings: CleanupSettings(look: .gray))
        for x in stride(from: 0.30, through: 0.70, by: 0.02) {
            let (r, _, _) = color(of: clean, at: CGPoint(x: x, y: 0.07))
            #expect(r > 0.97, "paper at \(x) is \(r)")
        }
    }

    @Test func keepsTheInkBlack() {
        let page = SyntheticPage(paper: (0.86, 0.8, 0.62), shadow: true).render()
        let clean = cleaner.render(page, analysis: cleaner.analyze(page), settings: CleanupSettings(look: .gray))
        let (r, _, _) = color(of: clean, at: SyntheticPage.blockCenter)
        #expect(r < 0.2)
    }

    @Test func photoLeavesTheColorsAlone() {
        let page = SyntheticPage(paper: (0.86, 0.8, 0.62)).render()
        let photo = cleaner.render(page, analysis: cleaner.analyze(page), settings: CleanupSettings(look: .photo))
        let (r, g, b) = color(of: photo, at: CGPoint(x: 0.05, y: 0.5))
        #expect(r - b > 0.15 && g < r)
    }

    @Test func blackAndWhiteHasOnlyTwoValues() {
        let page = SyntheticPage(shadow: true).render()
        let bw = cleaner.render(page, analysis: cleaner.analyze(page), settings: CleanupSettings(look: .blackAndWhite))
        var pixels = [UInt8](repeating: 0, count: Int(bw.extent.width) * Int(bw.extent.height) * 4)
        context.render(bw, toBitmap: &pixels, rowBytes: Int(bw.extent.width) * 4, bounds: bw.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        #expect(Set(stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }).isSubset(of: [0, 255]))
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
