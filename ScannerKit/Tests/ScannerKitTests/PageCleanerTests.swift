import CoreGraphics
import CoreImage
import CoreText
import ImageIO
import ScannerKit
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
        let small = bw
        var pixels = [UInt8](repeating: 0, count: Int(small.extent.width) * Int(small.extent.height) * 4)
        context.render(small, toBitmap: &pixels, rowBytes: Int(small.extent.width) * 4, bounds: small.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
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

/// An A4 page at about 100 dpi with real text, optionally with a stamp, a shaded header, a picture, a shadow or a rotation.
struct SyntheticPage {
    static let size = CGSize(width: 840, height: 1188)
    static let blockCenter = CGPoint(x: 0.5, y: 0.93)

    var paper: (CGFloat, CGFloat, CGFloat) = (0.95, 0.95, 0.93)
    var stamp = false
    var shadedHeader = false
    var picture = false
    var shadow = false
    var rotation: Double = 0

    func render() -> CIImage {
        let size = Self.size
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: paper.0, green: paper.1, blue: paper.2, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        context.saveGState()
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: rotation * .pi / 180)
        context.translateBy(x: -size.width / 2, y: -size.height / 2)

        let words = "The quick brown fox jumps over the lazy dog while the invoice waits for payment".split(separator: " ")
        let font = CTFontCreateWithName("Helvetica" as CFString, 17, nil)
        for line in 0..<30 {
            let start = line * 3 % words.count
            let text = (0..<9).map { String(words[(start + $0) % words.count]) }.joined(separator: " ")
            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.08, alpha: 1)])
            context.textPosition = CGPoint(x: 70, y: size.height - 140 - CGFloat(line) * 30)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.setFillColor(gray: 0.05, alpha: 1)
        context.fill(CGRect(x: 380, y: 60, width: 80, height: 40))
        if shadedHeader {
            context.setFillColor(gray: 0.7, alpha: 1)
            context.fill(CGRect(x: 70, y: size.height - 110, width: 700, height: 28))
        }
        if stamp {
            context.setStrokeColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 1)
            context.setLineWidth(5)
            context.stroke(CGRect(x: 520, y: 120, width: 220, height: 90))
        }
        if picture {
            context.setFillColor(red: 0.2, green: 0.3, blue: 0.25, alpha: 1)
            context.fill(CGRect(x: 120, y: 320, width: 600, height: 420))
        }
        context.restoreGState()

        var image = CIImage(cgImage: context.makeImage()!)
        if shadow {
            let gradient = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: size.width, y: size.height * 0.4),
                "inputColor0": CIColor(red: 0.45, green: 0.45, blue: 0.45), "inputColor1": CIColor(red: 1, green: 1, blue: 1),
            ])!.outputImage!.cropped(to: image.extent)
            image = image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: gradient])
        }
        return image
    }
}
