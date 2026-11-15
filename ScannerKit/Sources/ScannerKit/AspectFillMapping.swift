import CoreGraphics

/// Maps normalized image points to a view that shows the image scaled to fill, centered and cropped.
public struct AspectFillMapping: Equatable, Sendable {
    public let imageSize: CGSize
    public let viewSize: CGSize

    public init(imageSize: CGSize, viewSize: CGSize) {
        self.imageSize = imageSize
        self.viewSize = viewSize
    }

    public func viewPoint(for normalized: CGPoint) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * scale) / 2
        let offsetY = (viewSize.height - imageSize.height * scale) / 2
        return CGPoint(x: normalized.x * imageSize.width * scale + offsetX, y: normalized.y * imageSize.height * scale + offsetY)
    }
}
