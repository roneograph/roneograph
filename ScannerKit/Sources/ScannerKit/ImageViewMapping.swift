import CoreGraphics

/// Maps normalized image points to a view that shows the whole image centered, scaled to fit with bars where the proportions differ.
public struct ImageViewMapping: Sendable {
    public let imageSize: CGSize
    public let viewSize: CGSize

    public init(imageSize: CGSize, viewSize: CGSize) {
        self.imageSize = imageSize
        self.viewSize = viewSize
    }

    /// Where and how big the image is shown in the view.
    public var imageFrame: CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(origin: CGPoint(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2), size: size)
    }

    public func viewPoint(for normalized: CGPoint) -> CGPoint {
        let frame = imageFrame
        return CGPoint(x: frame.minX + normalized.x * frame.width, y: frame.minY + normalized.y * frame.height)
    }
}
