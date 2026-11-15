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
}
