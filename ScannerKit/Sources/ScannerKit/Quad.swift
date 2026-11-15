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

    /// The whole image.
    public static let full = Quad(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 1, y: 0), bottomRight: CGPoint(x: 1, y: 1), bottomLeft: CGPoint(x: 0, y: 1))

    /// Top left, top right, bottom right, bottom left.
    public var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    public init(corners: [CGPoint]) {
        precondition(corners.count == 4)
        self.init(topLeft: corners[0], topRight: corners[1], bottomRight: corners[2], bottomLeft: corners[3])
    }

    /// True when the corners turn the same way all around, so the quad does not fold over itself.
    public var isConvex: Bool {
        let c = corners
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = c[i], b = c[(i + 1) % 4], d = c[(i + 2) % 4]
            let cross = (b.x - a.x) * (d.y - b.y) - (b.y - a.y) * (d.x - b.x)
            guard abs(cross) > 1e-9 else { return false }
            if sign == 0 { sign = cross } else if (cross > 0) != (sign > 0) { return false }
        }
        return true
    }

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
}
