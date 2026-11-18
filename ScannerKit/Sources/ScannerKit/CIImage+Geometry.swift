import CoreImage

extension CIImage {
    /// The same image with its extent starting at zero.
    var atOrigin: CIImage {
        transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    /// The scale that brings the long side down to `longSide`; images already smaller keep a scale of 1.
    func scale(toLongSide longSide: CGFloat) -> CGFloat {
        min(1, longSide / max(extent.width, extent.height))
    }

    func scaled(by scale: CGFloat) -> CIImage {
        transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Scaled from the image clamped to its edges, then cropped to whole pixels, so its outer pixels do not fade into the transparency around it.
    func scaledKeepingEdges(by scale: CGFloat) -> CIImage {
        guard scale != 1 else { return self }
        let image = atOrigin
        return image.clampedToExtent().scaled(by: scale).cropped(to: image.scaled(by: scale).extent.integral)
    }
}
