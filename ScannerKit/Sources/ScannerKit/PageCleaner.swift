import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

public enum PageLook: String, Codable, Sendable, CaseIterable {
    case color, gray, blackAndWhite, photo
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
}

public struct CleanupSettings: Equatable, Codable, Sendable {
    /// Nil picks the look from the page content.
    public var look: PageLook?
    public var removeShadows: Bool
    public var whitePaper: Bool
    public var straighten: Bool
    /// From -1 to 1.
    public var brightness: Double
    /// From -1 to 1, black and white only: higher turns more faint ink black.
    public var threshold: Double

    public init(look: PageLook? = nil, removeShadows: Bool = true, whitePaper: Bool = true, straighten: Bool = true, brightness: Double = 0, threshold: Double = 0) {
        self.look = look
        self.removeShadows = removeShadows
        self.whitePaper = whitePaper
        self.straighten = straighten
        self.brightness = brightness
        self.threshold = threshold
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
}

/// Turns a flattened page photo into a clean page: upright, straight, even lighting, white paper, the right look.
public struct PageCleaner: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var backgroundSize: CGFloat = 512
        public var backgroundRadius: Double = 5
        public var backgroundBlur: Double = 6
        public var statisticsSize: CGFloat = 256
        public var textSize: CGFloat = 1400
        /// Paper is pushed to pure white from this fraction of its brightness.
        public var whitePoint: Float = 0.95
        /// The darkest ink is stretched to black, but never from lighter than this, so blank pages keep their noise light.
        public var maximumBlackPoint: Float = 0.45
        public var skewSize: CGFloat = 900
        public var inkDarkness: Float = 0.6
        public var colorChroma: Float = 0.12
        public var colorFractionForColor: Double = 0.002
        public var pictureDarkness: Float = 0.45
        public var pictureFractionForPhoto: Double = 0.15
        public var minimumSkew: Double = 0.15
        public var threshold: Double = 0.45

        public init() {}
    }

    public let configuration: Configuration
    private let context: CIContext

    public init(context: CIContext, configuration: Configuration = .init()) {
        self.context = context
        self.configuration = configuration
    }

    public func analyze(_ page: CIImage) -> PageAnalysis {
        let page = origin(page)
        let orientation = detectOrientation(page)
        let upright = page.oriented(orientation.imageOrientation)
        let paper = background(of: upright)
        let normalized = divide(upright, by: paper)
        let pictureFraction = pictureFraction(Bitmap(paper, longSide: configuration.statisticsSize, context: context))
        let colorFraction = colorFraction(Bitmap(normalized, longSide: configuration.statisticsSize, context: context))

        // Black and white is never picked automatically: gray blocks, faint stamps or pencil can vanish in it.
        let look: PageLook
        if pictureFraction >= configuration.pictureFractionForPhoto {
            look = .photo
        } else if colorFraction >= configuration.colorFractionForColor {
            look = .color
        } else {
            look = .gray
        }
        let skew = look == .photo ? 0 : skew(of: normalized)
        return PageAnalysis(orientation: orientation, skewDegrees: skew, suggestedLook: look, colorFraction: colorFraction, pictureFraction: pictureFraction)
    }

    public func render(_ page: CIImage, analysis: PageAnalysis, settings: CleanupSettings = .init()) -> CIImage {
        var image = origin(page).oriented(analysis.orientation.imageOrientation)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if settings.straighten, abs(analysis.skewDegrees) >= configuration.minimumSkew {
            image = rotated(image, degrees: -analysis.skewDegrees)
        }

        let look = settings.look ?? analysis.suggestedLook
        if look != .photo {
            if settings.removeShadows {
                image = divide(image, by: background(of: image))
            }
            if settings.whitePaper {
                image = stretched(whitened(image))
            }
            image = image.applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 1.5, kCIInputIntensityKey: 0.5]).cropped(to: image.extent)
        }
        if settings.brightness != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: settings.brightness])
        }

        switch look {
        case .color:
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.1])
        case .gray:
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        case .blackAndWhite:
            let threshold = configuration.threshold * pow(2, settings.threshold)
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
                .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": threshold])
        case .photo:
            break
        }
        return image.cropped(to: CGRect(origin: .zero, size: image.extent.size)).applyingFilter("CIColorClamp")
    }

    // MARK: Lighting

    /// The paper without the ink: dark details smaller than the radius are removed, then the result is blurred.
    func background(of image: CIImage) -> CIImage {
        let extent = image.extent
        let scale = min(1, configuration.backgroundSize / max(extent.width, extent.height))
        let small = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY).scaledBy(x: scale, y: scale))
        let smallExtent = small.extent
        let paper = small.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: configuration.backgroundRadius])
            .applyingGaussianBlur(sigma: configuration.backgroundBlur)
            .cropped(to: smallExtent)
        return paper.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale).concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY)))
            .cropped(to: extent)
    }

    func divide(_ image: CIImage, by background: CIImage) -> CIImage {
        let filter = CIFilter.divideBlendMode()
        filter.inputImage = background
        filter.backgroundImage = image
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    /// Scales each channel so the paper becomes pure white, which also removes color casts.
    private func whitened(_ image: CIImage) -> CIImage {
        let bitmap = Bitmap(image, longSide: configuration.statisticsSize, context: context)
        var channels: [[Float]] = [[], [], []]
        for i in 0..<bitmap.count {
            let (r, g, b) = bitmap.rgb(i)
            channels[0].append(r)
            channels[1].append(g)
            channels[2].append(b)
        }
        let gains = channels.map { values in
            let paper = max(0.05, Bitmap.percentile(values, 0.9))
            return CGFloat(1 / (paper * configuration.whitePoint))
        }
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: gains[0], y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: gains[1], z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: gains[2], w: 0)
        return (filter.outputImage ?? image).applyingFilter("CIColorClamp")
    }

    /// Stretches the darkest ink to black, so faint pencil or a gray print gets readable contrast.
    private func stretched(_ image: CIImage) -> CIImage {
        let bitmap = Bitmap(image, longSide: configuration.statisticsSize, context: context)
        let black = min(configuration.maximumBlackPoint, Bitmap.percentile((0..<bitmap.count).map(bitmap.luminance), 0.002))
        guard black > 0.01 else { return image }
        let gain = CGFloat(1 / (1 - black)), offset = CGFloat(-black / (1 - black))
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        filter.biasVector = CIVector(x: offset, y: offset, z: offset, w: 0)
        return (filter.outputImage ?? image).applyingFilter("CIColorClamp")
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
    private func detectOrientation(_ page: CIImage) -> PageOrientation {
        let extent = page.extent
        let scale = min(1, configuration.textSize / max(extent.width, extent.height))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(ciImage: page.transformed(by: CGAffineTransform(scaleX: scale, y: scale))).perform([request])

        var votes: [PageOrientation: Double] = [:]
        for line in request.results ?? [] {
            let dx = Double(line.topRight.x - line.topLeft.x) * extent.width
            let dy = Double(line.topRight.y - line.topLeft.y) * extent.height
            let orientation: PageOrientation = abs(dx) >= abs(dy) ? (dx > 0 ? .up : .down) : (dy > 0 ? .right : .left)
            votes[orientation, default: 0] += hypot(dx, dy)
        }
        return votes.max { $0.value < $1.value }?.key ?? .up
    }

    private func skew(of normalized: CIImage) -> Double {
        let bitmap = Bitmap(normalized, longSide: configuration.skewSize, context: context)
        let ink = (0..<bitmap.count).map { bitmap.luminance($0) < configuration.inkDarkness }
        return SkewEstimator().skew(ink: ink, width: bitmap.width, height: bitmap.height)
    }

    // MARK: Geometry

    private func origin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    /// Rotates around the center, keeping the size; the corners are filled with the nearest edge.
    private func rotated(_ image: CIImage, degrees: Double) -> CIImage {
        let extent = image.extent
        let transform = CGAffineTransform(translationX: extent.midX, y: extent.midY)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -extent.midX, y: -extent.midY)
        return image.clampedToExtent().transformed(by: transform).cropped(to: extent)
    }
}
