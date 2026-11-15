import Foundation

/// Turns the name of a scan into its file name: "Lumen Energy invoice" can become "2026-11-12-lumen-energy-invoice".
public struct FileNameFormat: Equatable, Sendable, Codable {
    public enum Separator: String, Equatable, Sendable, Codable, CaseIterable {
        case space, dash, underscore

        public var character: String {
            switch self {
            case .space: " "
            case .dash: "-"
            case .underscore: "_"
            }
        }
    }

    public var datePrefix: Bool
    public var separator: Separator
    public var lowercase: Bool

    public init(datePrefix: Bool = false, separator: Separator = .space, lowercase: Bool = false) {
        self.datePrefix = datePrefix
        self.separator = separator
        self.lowercase = lowercase
    }

    /// With dashes or underscores, any run of characters other than letters and digits becomes one separator.
    /// A name that already starts or ends with the date does not get it twice.
    public func fileName(name: String, date: Date) -> String {
        let iso = FileNamer.isoDate(date)
        var rest = name.trimmingCharacters(in: .whitespaces)
        var dated = datePrefix
        if rest.hasPrefix(iso) {
            rest = String(rest.dropFirst(iso.count))
            dated = true
        } else if datePrefix, rest.hasSuffix(iso) {
            rest = String(rest.dropLast(iso.count))
        }
        var words = separator == .space
            ? rest.split(whereSeparator: \.isWhitespace).map(String.init)
            : rest.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        if lowercase { words = words.map { $0.lowercased() } }
        if dated { words.insert(iso, at: 0) }
        return FileNamer().finalName(words.joined(separator: separator.character), fallback: iso)
    }
}
