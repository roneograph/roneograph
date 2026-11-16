import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

public enum PageLook: String, Codable, Sendable, CaseIterable {
    case gray, color

    /// Pages saved with a look that no longer exists become gray when they were black and white, color otherwise.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? (raw == "blackAndWhite" ? .gray : .color)
    }
}

/// How a page should be turned to be upright.
public enum PageOrientation: String, Codable, Sendable, CaseIterable {
    case up, right, down, left

    var imageOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .right: .right
        case .down: .down
        case .left: .left
        }
    }

    /// The orientation a quarter turn further.
    public func turned(clockwise: Bool) -> PageOrientation {
        switch self {
        case .up: clockwise ? .right : .left
        case .right: clockwise ? .down : .up
        case .down: clockwise ? .left : .right
        case .left: clockwise ? .up : .down
        }
    }
}

public struct CleanupSettings: Equatable, Codable, Sendable {
    /// Nil picks the look from the page content.
    public var look: PageLook?

    public init(look: PageLook? = nil) {
        self.look = look
    }
}

public struct PageAnalysis: Equatable, Codable, Sendable {
    public var orientation: PageOrientation
    /// Angle of the text lines once upright, counterclockwise.
    public var skewDegrees: Double
    public var suggestedLook: PageLook
    /// Share of the page covered by colored ink.
    public var colorFraction: Double
    /// Share of the page covered by large dark areas, such as pictures.
    public var pictureFraction: Double
    /// Median height of the text lines as a share of the page's long side, nil without enough text.
    public var textLineHeight: Double?

    public init(orientation: PageOrientation, skewDegrees: Double, suggestedLook: PageLook, colorFraction: Double, pictureFraction: Double, textLineHeight: Double?) {
        self.orientation = orientation
        self.skewDegrees = skewDegrees
        self.suggestedLook = suggestedLook
        self.colorFraction = colorFraction
        self.pictureFraction = pictureFraction
        self.textLineHeight = textLineHeight
    }
}

/// Turns a flattened page photo into a clean page: upright, straight, even lighting, white paper, the right look.
public struct PageCleaner: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var backgroundSize: CGFloat = 512
        public var backgroundRadius: Double = 5
        public var backgroundBlur: Double = 1.5
        /// The background is never darker than this share of the page-wide paper, so large dark blocks stay ink.
        public var deepestShadow: Double = 0.3
        public var lightingSize: CGFloat = 128
        public var lightingRadius: Double = 12
        public var statisticsSize: CGFloat = 256
        public var textSize: CGFloat = 1400
        /// Anything at least this bright relative to the paper becomes pure white, which hides leftover shadows and noise.
        public var paperKnee: Double = 0.8
        /// Darkens the ink below the knee, for faint pencil and thin strokes.
        public var inkGamma: Double = 1.4
        public var skewSize: CGFloat = 900
        public var inkDarkness: Float = 0.6
        public var colorChroma: Float = 0.12
        public var colorFractionForColor: Double = 0.002
        public var pictureDarkness: Float = 0.45
        /// Above this, shadow removal could wash out the pictures, so the page is only evened by its paper color.
        public var pictureFractionForPaperColor: Double = 0.15
        public var minimumSkew: Double = 0.15
        public var minimumLinesForSize = 5

        public init() {}
    }

    public let configuration: Configuration
    private let context: CIContext

    public init(context: CIContext, configuration: Configuration = .init()) {
        self.context = context
        self.configuration = configuration
    }

    public func analyze(_ page: CIImage) -> PageAnalysis {
        let page = page.atOrigin
        let (orientation, textLineHeight) = detectOrientation(page)
        let upright = page.oriented(orientation.imageOrientation)
        let paper = background(of: upright)
        let normalized = divide(upright, by: paper)
        let pictureFraction = pictureFraction(Bitmap(paper, longSide: configuration.statisticsSize, context: context))
        let colorFraction = colorFraction(Bitmap(normalized, longSide: configuration.statisticsSize, context: context))
        let look: PageLook = colorFraction >= configuration.colorFractionForColor ? .color : .gray
        return PageAnalysis(orientation: orientation, skewDegrees: skew(of: normalized), suggestedLook: look, colorFraction: colorFraction, pictureFraction: pictureFraction, textLineHeight: textLineHeight)
    }

    public func render(_ page: CIImage, analysis: PageAnalysis, settings: CleanupSettings = .init()) -> CIImage {
        var image = page.atOrigin.oriented(analysis.orientation.imageOrientation).atOrigin
        if abs(analysis.skewDegrees) >= configuration.minimumSkew {
            image = rotated(image, degrees: -analysis.skewDegrees)
        }

        let paper = analysis.pictureFraction >= configuration.pictureFractionForPaperColor ? paperColor(of: image) : background(of: image)
        image = whitePaper(divide(image, by: paper))
        switch settings.look ?? analysis.suggestedLook {
        case .color:
            break
        case .gray:
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        }
        return image.cropped(to: CGRect(origin: .zero, size: image.extent.size)).applyingFilter("CIColorClamp")
    }

    // MARK: Lighting

    /// The paper without the ink: a closing removes dark details smaller than the radius while keeping the edges of shadows where they are.
    func background(of image: CIImage) -> CIImage {
        let extent = image.extent
        let scale = image.scale(toLongSide: configuration.backgroundSize)
        let small = image.atOrigin.scaled(by: scale)
        let smallExtent = small.extent
        let paper = small.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: configuration.backgroundRadius])
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: configuration.backgroundRadius])
            .applyingGaussianBlur(sigma: configuration.backgroundBlur)
            .cropped(to: smallExtent)
        let floor = lighting(of: small).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: configuration.deepestShadow, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: configuration.deepestShadow, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: configuration.deepestShadow, w: 0),
        ])
        return paper.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: floor])
            .cropped(to: smallExtent)
            .clampedToExtent()
            .scaled(by: 1 / scale)
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    /// The paper brightness at the scale of the whole page, ignoring shadows, blocks and pictures.
    private func lighting(of image: CIImage) -> CIImage {
        let scale = image.scale(toLongSide: configuration.lightingSize)
        return image.scaled(by: scale).clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: configuration.lightingRadius])
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: configuration.lightingRadius / 2])
            .applyingGaussianBlur(sigma: configuration.lightingRadius)
            .scaled(by: 1 / scale)
            .cropped(to: image.extent)
    }

    func divide(_ image: CIImage, by background: CIImage) -> CIImage {
        let filter = CIFilter.divideBlendMode()
        filter.inputImage = background
        filter.backgroundImage = image
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    /// The paper color of the whole page, as a uniform image.
    private func paperColor(of image: CIImage) -> CIImage {
        let bitmap = Bitmap(image, longSide: configuration.statisticsSize, context: context)
        let channels = (0..<3).map { c in (0..<bitmap.count).map { bitmap.pixels[$0 * 4 + c] } }
        let paper = channels.map { CGFloat(max(0.05, Bitmap.percentile($0, 0.9))) }
        return CIImage(color: CIColor(red: paper[0], green: paper[1], blue: paper[2], colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!).cropped(to: image.extent)
    }

    /// Pushes everything above the knee to white and darkens the ink below it.
    private func whitePaper(_ image: CIImage) -> CIImage {
        let gain = CGFloat(1 / configuration.paperKnee)
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        return (filter.outputImage ?? image)
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": configuration.inkGamma])
    }

    // MARK: Content

    /// Share of the page covered by large dark areas, much darker than the paper.
    private func pictureFraction(_ paper: Bitmap) -> Double {
        let luminances = (0..<paper.count).map(paper.luminance)
        let white = Bitmap.percentile(luminances, 0.9)
        let dark = luminances.filter { $0 < white * configuration.pictureDarkness }.count
        return Double(dark) / Double(max(1, paper.count))
    }

    private func colorFraction(_ normalized: Bitmap) -> Double {
        var colored = 0
        for i in 0..<normalized.count {
            let (r, g, b) = normalized.rgb(i)
            let chroma = max(r, g, b) - min(r, g, b)
            if chroma >= configuration.colorChroma, normalized.luminance(i) < 0.85 { colored += 1 }
        }
        return Double(colored) / Double(max(1, normalized.count))
    }

    // MARK: Text

    /// The accurate recognizer reads text in any orientation; the direction of its lines says how the page is turned.
    private func detectOrientation(_ page: CIImage) -> (PageOrientation, Double?) {
        let extent = page.extent
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(ciImage: page.scaled(by: page.scale(toLongSide: configuration.textSize))).perform([request])

        var votes: [PageOrientation: Double] = [:]
        var heights: [Double] = []
        for line in request.results ?? [] {
            let dx = Double(line.topRight.x - line.topLeft.x) * extent.width
            let dy = Double(line.topRight.y - line.topLeft.y) * extent.height
            let orientation: PageOrientation = abs(dx) >= abs(dy) ? (dx > 0 ? .up : .down) : (dy > 0 ? .right : .left)
            votes[orientation, default: 0] += hypot(dx, dy)
            if (line.topCandidates(1).first?.string.count ?? 0) >= 4 {
                heights.append(hypot(Double(line.topLeft.x - line.bottomLeft.x) * extent.width, Double(line.topLeft.y - line.bottomLeft.y) * extent.height))
            }
        }
        let orientation = votes.max { $0.value < $1.value }?.key ?? .up
        guard heights.count >= configuration.minimumLinesForSize else { return (orientation, nil) }
        return (orientation, heights.sorted()[heights.count / 2] / max(extent.width, extent.height))
    }

    private func skew(of normalized: CIImage) -> Double {
        let bitmap = Bitmap(normalized, longSide: configuration.skewSize, context: context)
        let ink = (0..<bitmap.count).map { bitmap.luminance($0) < configuration.inkDarkness }
        return SkewEstimator().skew(ink: ink, width: bitmap.width, height: bitmap.height)
    }

    // MARK: Geometry

    /// Rotates around the center, keeping the size; the corners are filled with the nearest edge.
    private func rotated(_ image: CIImage, degrees: Double) -> CIImage {
        let extent = image.extent
        let transform = CGAffineTransform(translationX: extent.midX, y: extent.midY)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -extent.midX, y: -extent.midY)
        return image.clampedToExtent().transformed(by: transform).cropped(to: extent)
    }
}
