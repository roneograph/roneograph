import CoreGraphics

/// The four corners of a page, normalized to the image (0...1) with the origin at the top left.
public struct Quad: Equatable, Sendable, Codable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// Builds a quad from points normalized with the origin at the bottom left, as Vision returns them.
    public init(lowerLeftOriginTopLeft topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
        self.init(topLeft: flip(topLeft), topRight: flip(topRight), bottomRight: flip(bottomRight), bottomLeft: flip(bottomLeft))
    }

    public var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Area as a fraction of the image.
    public var area: CGFloat {
        let c = corners
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = c[i], b = c[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// The largest distance any corner moved between the two quads.
    public func maxCornerDistance(to other: Quad) -> CGFloat {
        zip(corners, other.corners).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
    }

    /// Corners in pixels of an image of the given size, still with the origin at the top left.
    public func scaled(to size: CGSize) -> [CGPoint] {
        corners.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }
}
