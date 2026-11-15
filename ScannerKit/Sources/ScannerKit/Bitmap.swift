import CoreImage

/// A small linear RGB rendering of an image, for statistics.
struct Bitmap {
    let width: Int
    let height: Int
    /// RGBA, linear sRGB, row 0 at the top.
    let pixels: [Float]

    init(_ image: CIImage, longSide: CGFloat, context: CIContext) {
        let extent = image.extent
        let scale = image.scale(toLongSide: longSide)
        let small = image.atOrigin
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        width = max(1, Int(extent.width * scale))
        height = max(1, Int(extent.height * scale))
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(small, toBitmap: &pixels, rowBytes: width * 16, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        self.pixels = pixels
    }

    var count: Int { width * height }

    func rgb(_ i: Int) -> (Float, Float, Float) {
        (pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2])
    }

    func luminance(_ i: Int) -> Float {
        let (r, g, b) = rgb(i)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// The value below which `fraction` of the samples fall.
    static func percentile(_ values: [Float], _ fraction: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
    }
}
