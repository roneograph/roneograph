/// A tiny grayscale fingerprint of a page's content, used to tell a new page from the one just captured.
public struct PageSignature: Equatable, Sendable {
    public static let width = 12
    public static let height = 16

    /// Brightness of each cell, minus the mean, so exposure changes do not count as a new page.
    public let values: [Float]

    public init(luminance: [Float]) {
        precondition(luminance.count == Self.width * Self.height)
        let mean = luminance.reduce(0, +) / Float(luminance.count)
        values = luminance.map { $0 - mean }
    }

    /// Mean absolute difference, 0 for identical content.
    public func distance(to other: PageSignature) -> Double {
        Double(zip(values, other.values).map { abs($0 - $1) }.reduce(0, +)) / Double(values.count)
    }
}
