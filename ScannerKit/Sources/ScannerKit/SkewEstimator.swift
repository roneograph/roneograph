import Foundation

/// Finds the angle of the text lines: when the page is rotated by the right angle, ink piles up
/// in a few rows separated by blank rows, so the row profile has the highest variance.
struct SkewEstimator {
    private let maximumDegrees: Double = 10
    private let coarseStep: Double = 0.5
    private let fineStep: Double = 0.05
    /// Below this share of ink pixels, there is not enough text to measure.
    private let minimumInk: Double = 0.003

    /// Angle in degrees, counterclockwise, of the text in an image whose row 0 is at the top.
    func skew(ink: [Bool], width: Int, height: Int) -> Double {
        var points: [(x: Double, y: Double)] = []
        for y in 0..<height {
            for x in 0..<width where ink[y * width + x] {
                points.append((Double(x) - Double(width) / 2, Double(y) - Double(height) / 2))
            }
        }
        guard Double(points.count) >= minimumInk * Double(width * height) else { return 0 }

        let diagonal = Int(hypot(Double(width), Double(height))) + 2
        var bins = [Int](repeating: 0, count: diagonal)
        func score(_ degrees: Double) -> Double {
            let radians = degrees * .pi / 180
            let s = sin(radians), c = cos(radians)
            for i in bins.indices { bins[i] = 0 }
            for p in points {
                let row = Int(p.y * c + p.x * s) + diagonal / 2
                if row >= 0, row < diagonal { bins[row] += 1 }
            }
            return bins.reduce(0) { $0 + Double($1 * $1) }
        }
        func best(in range: ClosedRange<Double>, step: Double) -> Double {
            stride(from: range.lowerBound, through: range.upperBound, by: step)
                .map { (degrees: $0, score: score($0)) }
                .max { $0.score < $1.score }?.degrees ?? 0
        }
        let coarse = best(in: -maximumDegrees...maximumDegrees, step: coarseStep)
        return best(in: (coarse - coarseStep)...(coarse + coarseStep), step: fineStep)
    }
}
