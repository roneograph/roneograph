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

    /// Where and how big the image is shown in the view.
    public var imageFrame: CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let ratios = (viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scale = scaling == .fill ? max(ratios.0, ratios.1) : min(ratios.0, ratios.1)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(origin: CGPoint(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2), size: size)
    }

    public func viewPoint(for normalized: CGPoint) -> CGPoint {
        let frame = imageFrame
        return CGPoint(x: frame.minX + normalized.x * frame.width, y: frame.minY + normalized.y * frame.height)
    }
}
