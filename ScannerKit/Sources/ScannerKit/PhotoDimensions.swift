import CoreMedia

extension CMVideoDimensions {
    /// The largest size up to 12 MP: a 150 dpi page needs a few, and 48 MP photos cost time, memory and storage for nothing.
    public static func photoSize(among supported: [CMVideoDimensions]) -> CMVideoDimensions? {
        let fitting = supported.filter { $0.pixels <= 4032 * 3024 }
        return fitting.max { $0.pixels < $1.pixels } ?? supported.min { $0.pixels < $1.pixels }
    }

    private var pixels: Int { Int(width) * Int(height) }
}
