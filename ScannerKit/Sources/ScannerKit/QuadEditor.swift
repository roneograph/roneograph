import CoreGraphics

/// Moves the corners and sides of a page outline by hand, in normalized image coordinates.
public struct QuadEditor: Sendable {
    public enum Handle: Hashable, Sendable {
        /// 0 top left, 1 top right, 2 bottom right, 3 bottom left.
        case corner(Int)
        /// The side from corner `i` to corner `i + 1`: 0 top, 1 right, 2 bottom, 3 left.
        case side(Int)
    }

    public static let handles: [Handle] = (0..<4).map(Handle.corner) + (0..<4).map(Handle.side)

    /// How close a corner must come to a target to snap onto it.
    public var snapDistance: CGFloat = 0.025
    /// Outlines smaller than this share of the image are refused.
    public var minimumArea: CGFloat = 0.01

    public init() {}

    public func position(of handle: Handle, in quad: Quad) -> CGPoint {
        let c = quad.corners
        switch handle {
        case .corner(let i): return c[i]
        case .side(let i):
            let a = c[i], b = c[(i + 1) % 4]
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
    }

    /// The outline with the handle moved to `point`, kept inside the image; corners snap to nearby targets.
    /// Moves that would fold the outline or make it tiny are refused: the outline stays as it was.
    public func moving(_ handle: Handle, in quad: Quad, to point: CGPoint, snapTargets: [CGPoint] = []) -> Quad {
        var corners = quad.corners
        switch handle {
        case .corner(let i):
            corners[i] = snapped(clamped(point), to: snapTargets)
        case .side(let i):
            let current = position(of: handle, in: quad)
            var dx = point.x - current.x, dy = point.y - current.y
            for j in [i, (i + 1) % 4] {
                dx = min(max(dx, -corners[j].x), 1 - corners[j].x)
                dy = min(max(dy, -corners[j].y), 1 - corners[j].y)
            }
            for j in [i, (i + 1) % 4] {
                corners[j] = CGPoint(x: corners[j].x + dx, y: corners[j].y + dy)
            }
        }
        let moved = Quad(corners: corners)
        return moved.isConvex && moved.area >= minimumArea ? moved : quad
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    private func snapped(_ p: CGPoint, to targets: [CGPoint]) -> CGPoint {
        let nearest = targets.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }
        guard let nearest, hypot(nearest.x - p.x, nearest.y - p.y) <= snapDistance else { return p }
        return nearest
    }
}
