import CoreGraphics

/// Maps normalized image points to a view that shows the image centered, scaled to fit or to fill.
public struct ImageViewMapping: Equatable, Sendable {
    public enum Scaling: Sendable {
        /// The whole image is visible, with bars where the proportions differ.
        case fit
        /// The image covers the view and its overflow is cropped.
        case fill
    }

    public let imageSize: CGSize
    public let viewSize: CGSize
    public let scaling: Scaling

    public init(imageSize: CGSize, viewSize: CGSize, scaling: Scaling) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        self.scaling = scaling
    }

    public func viewPoint(for normalized: CGPoint) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let ratios = (viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scale = scaling == .fill ? max(ratios.0, ratios.1) : min(ratios.0, ratios.1)
        let offsetX = (viewSize.width - imageSize.width * scale) / 2
        let offsetY = (viewSize.height - imageSize.height * scale) / 2
        return CGPoint(x: normalized.x * imageSize.width * scale + offsetX, y: normalized.y * imageSize.height * scale + offsetY)
    }
}
