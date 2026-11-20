import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

public enum PageLook: String, Codable, Sendable, CaseIterable {
    case gray, color
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

    /// The orientation a quarter turn clockwise further.
    public var turned: PageOrientation {
        switch self {
        case .up: .right
        case .right: .down
        case .down: .left
        case .left: .up
        }
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
public struct PageCleaner: Sendable {
    private let backgroundSize: CGFloat = 512
    private let backgroundRadius: Double = 5
    private let backgroundBlur: Double = 1.5
    /// The background is never darker than this share of the page-wide paper, so large dark blocks stay ink.
    private let deepestShadow: Double = 0.3
    private let lightingSize: CGFloat = 128
    private let lightingRadius: Double = 12
    private let statisticsSize: CGFloat = 256
    /// Anything at least this bright relative to the paper becomes pure white, which hides leftover shadows and noise.
    private let paperKnee: Double = 0.8
    /// Darkens the ink below the knee, for faint pencil and thin strokes.
    private let inkGamma: Double = 1.4
    private let skewSize: CGFloat = 900
    private let inkDarkness: Float = 0.6
    private let colorChroma: Float = 0.12
    private let colorFractionForColor: Double = 0.002
    private let pictureDarkness: Float = 0.45
    /// Above this, shadow removal could wash out the pictures, so the page is only evened by its paper color.
    private let pictureFractionForPaperColor: Double = 0.15
    private let minimumSkew: Double = 0.15
    private let edgeSize: CGFloat = 600
    /// How far in from each side dark areas touching the side are taken for the table or a shadow around the sheet, as a share of the short side.
    private let edgeBand: Double = 0.04
    private let edgeDarkness: Float = 0.85

    private let context: CIContext
    private let readOrientation: @Sendable (CIImage) async throws -> (PageOrientation, Double?)

    /// `readOrientation` tells how the page is turned and the median height of its text lines, nil without enough text.
    public init(context: CIContext, readOrientation: @escaping @Sendable (CIImage) async throws -> (PageOrientation, Double?) = PageCleaner.readOrientation) {
        self.context = context
        self.readOrientation = readOrientation
    }

    public func analyze(_ page: CIImage) async throws -> PageAnalysis {
        let page = page.atOrigin
        let (orientation, textLineHeight) = try await orientationAndTextLineHeight(of: page)
        let upright = page.oriented(orientation.imageOrientation)
        let paper = background(of: upright)
        let normalized = divide(upright, by: paper)
        let pictureFraction = pictureFraction(Bitmap(paper, longSide: statisticsSize, context: context))
        let colorFraction = colorFraction(Bitmap(normalized, longSide: statisticsSize, context: context))
        let look: PageLook = colorFraction >= colorFractionForColor ? .color : .gray
        return PageAnalysis(orientation: orientation, skewDegrees: skew(of: normalized), suggestedLook: look, colorFraction: colorFraction, pictureFraction: pictureFraction, textLineHeight: textLineHeight)
    }

    public func render(_ page: CIImage, analysis: PageAnalysis, look: PageLook) -> CIImage {
        var image = page.atOrigin.oriented(analysis.orientation.imageOrientation).atOrigin
        let paper = analysis.pictureFraction >= pictureFractionForPaperColor ? paperColor(of: image) : background(of: image)
        image = whitePaper(divide(image, by: paper))
        image = whiteningEdges(of: image)
        if abs(analysis.skewDegrees) >= minimumSkew {
            image = rotated(image, degrees: -analysis.skewDegrees)
        }
        switch look {
        case .color:
            break
        case .gray:
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        }
        return image.applyingFilter("CIColorClamp")
    }

    // MARK: Lighting

    /// The paper without the ink: a closing removes dark details smaller than the radius while keeping the edges of shadows where they are.
    private func background(of image: CIImage) -> CIImage {
        let extent = image.extent
        let scale = image.scale(toLongSide: backgroundSize)
        let small = image.atOrigin.scaled(by: scale)
        let smallExtent = small.extent
        let paper = small.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: backgroundRadius])
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: backgroundRadius])
            .applyingGaussianBlur(sigma: backgroundBlur)
            .cropped(to: smallExtent)
        let floor = lighting(of: small).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: deepestShadow, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: deepestShadow, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: deepestShadow, w: 0),
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
        let scale = image.scale(toLongSide: lightingSize)
        return image.scaled(by: scale).clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: lightingRadius])
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: lightingRadius / 2])
            .applyingGaussianBlur(sigma: lightingRadius)
            .scaled(by: 1 / scale)
            .cropped(to: image.extent)
    }

    private func divide(_ image: CIImage, by background: CIImage) -> CIImage {
        let filter = CIFilter.divideBlendMode()
        filter.inputImage = background
        filter.backgroundImage = image
        return (filter.outputImage ?? image).cropped(to: image.extent)
    }

    /// The paper color of the whole page, as a uniform image.
    private func paperColor(of image: CIImage) -> CIImage {
        let bitmap = Bitmap(image, longSide: statisticsSize, context: context)
        let channels = (0..<3).map { c in (0..<bitmap.count).map { bitmap.pixels[$0 * 4 + c] } }
        let paper = channels.map { CGFloat(max(0.05, Bitmap.percentile($0, 0.9))) }
        return CIImage(color: CIColor(red: paper[0], green: paper[1], blue: paper[2], colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!).cropped(to: image.extent)
    }

    /// Pushes everything above the knee to white and darkens the ink below it.
    private func whitePaper(_ image: CIImage) -> CIImage {
        let gain = CGFloat(1 / paperKnee)
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        return (filter.outputImage ?? image)
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": inkGamma])
    }

    // MARK: Edges

    /// Turns white the dark areas that touch a side of the page and stay close to it: the table, the next sheet or a shadow left by the crop.
    /// What reaches further in, such as a full-bleed header or picture, is kept whole.
    private func whiteningEdges(of image: CIImage) -> CIImage {
        let bitmap = Bitmap(image, longSide: edgeSize, context: context)
        let (width, height) = (bitmap.width, bitmap.height)
        let band = max(2, Int(Double(min(width, height)) * edgeBand))
        let isDark = (0..<bitmap.count).map { bitmap.luminance($0) < edgeDarkness }
        var visited = [Bool](repeating: false, count: bitmap.count)
        var mask = [UInt8](repeating: 0, count: bitmap.count)
        let rows: [Int] = (0..<width).flatMap { x -> [Int] in [x, (height - 1) * width + x] }
        let columns: [Int] = (0..<height).flatMap { y -> [Int] in [y * width, y * width + width - 1] }
        let borders = rows + columns
        for seed in borders where isDark[seed] && !visited[seed] {
            var stack = [seed]
            var members: [Int] = []
            var escapes = false
            visited[seed] = true
            while let i = stack.popLast() {
                members.append(i)
                let (x, y) = (i % width, i / width)
                if min(x, y, width - 1 - x, height - 1 - y) >= band { escapes = true }
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let n = ny * width + nx
                    if isDark[n] && !visited[n] {
                        visited[n] = true
                        stack.append(n)
                    }
                }
            }
            if !escapes { for i in members { mask[i] = 255 } }
        }
        guard mask.contains(255), let provider = CGDataProvider(data: Data(mask) as CFData),
              let cgMask = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return image }
        let extent = image.extent
        let scaledMask = CIImage(cgImage: cgMask)
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1.5])
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
            .clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
        let white = CIImage(color: .white).cropped(to: extent)
        return white.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: scaledMask]).cropped(to: extent)
    }

    // MARK: Content

    /// Share of the page covered by large dark areas, much darker than the paper.
    private func pictureFraction(_ paper: Bitmap) -> Double {
        let luminances = (0..<paper.count).map(paper.luminance)
        let white = Bitmap.percentile(luminances, 0.9)
        let dark = luminances.filter { $0 < white * pictureDarkness }.count
        return Double(dark) / Double(max(1, paper.count))
    }

    private func colorFraction(_ normalized: Bitmap) -> Double {
        var colored = 0
        for i in 0..<normalized.count {
            let (r, g, b) = normalized.rgb(i)
            let chroma = max(r, g, b) - min(r, g, b)
            if chroma >= colorChroma, normalized.luminance(i) < 0.85 { colored += 1 }
        }
        return Double(colored) / Double(max(1, normalized.count))
    }

    // MARK: Text

    /// A page whose text cannot be read is taken for upright, which the user can still turn.
    private func orientationAndTextLineHeight(of page: CIImage) async throws -> (PageOrientation, Double?) {
        do {
            return try await readOrientation(page)
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            return (.up, nil)
        }
    }

    /// The accurate recognizer reads text in any orientation; the direction of its lines says how the page is turned,
    /// and their median height, as a share of the page's long side, how big the text is.
    public static func readOrientation(of page: CIImage) async throws -> (PageOrientation, Double?) {
        let textSize: CGFloat = 1400, minimumLinesForSize = 5
        let extent = page.extent
        var request = RecognizeTextRequest.page()
        request.usesLanguageCorrection = false
        let lines = try await request.perform(on: page.scaled(by: page.scale(toLongSide: textSize)))

        var votes: [PageOrientation: Double] = [:]
        var heights: [Double] = []
        for line in lines {
            let dx = Double(line.topRight.x - line.topLeft.x) * extent.width
            let dy = Double(line.topRight.y - line.topLeft.y) * extent.height
            let orientation: PageOrientation = abs(dx) >= abs(dy) ? (dx > 0 ? .up : .down) : (dy > 0 ? .right : .left)
            votes[orientation, default: 0] += hypot(dx, dy)
            if (line.topCandidates(1).first?.string.count ?? 0) >= 4 {
                heights.append(hypot(Double(line.topLeft.x - line.bottomLeft.x) * extent.width, Double(line.topLeft.y - line.bottomLeft.y) * extent.height))
            }
        }
        let orientation = votes.max { $0.value < $1.value }?.key ?? .up
        guard heights.count >= minimumLinesForSize else { return (orientation, nil) }
        return (orientation, heights.sorted()[heights.count / 2] / max(extent.width, extent.height))
    }

    /// The angle of the text lines, from the ink away from the sides, where a strip of table or a shadow would outweigh the text.
    private func skew(of normalized: CIImage) -> Double {
        let bitmap = Bitmap(normalized, longSide: skewSize, context: context)
        let (width, height) = (bitmap.width, bitmap.height)
        let band = Int(Double(min(width, height)) * edgeBand)
        let ink = (0..<bitmap.count).map { i in
            let (x, y) = (i % width, i / width)
            return min(x, y, width - 1 - x, height - 1 - y) >= band && bitmap.luminance(i) < inkDarkness
        }
        return SkewEstimator().skew(ink: ink, width: width, height: height)
    }

    // MARK: Geometry

    /// Rotates a clean page on white paper large enough to keep all of it.
    private func rotated(_ image: CIImage, degrees: Double) -> CIImage {
        let rotation = CGAffineTransform(rotationAngle: degrees * .pi / 180)
        let page = CIImage(color: .white).cropped(to: image.extent).transformed(by: rotation)
        let extent = page.extent.insetBy(dx: 0.5, dy: 0.5).integral
        let white = CIImage(color: .white).cropped(to: extent)
        return image.clampedToExtent().transformed(by: rotation)
            .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: white, kCIInputMaskImageKey: page])
            .cropped(to: extent).atOrigin
    }
}
