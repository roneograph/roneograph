import Foundation

extension Date {
    /// Noon on an ISO day such as "2026-11-12" in the current time zone, as a date printed on a document is kept.
    public static func day(_ iso: String) -> Date {
        let parts = iso.split(separator: "-").map { Int($0)! }
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }
}
