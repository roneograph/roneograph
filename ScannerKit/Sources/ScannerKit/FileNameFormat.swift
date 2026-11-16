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

    public enum DatePosition: String, Equatable, Sendable, Codable, CaseIterable {
        case none, start, end
    }

    public enum DateStyle: String, Equatable, Sendable, Codable, CaseIterable {
        /// 2026-11-12
        case day
        /// 20261112
        case compactDay
        /// 2026-11
        case month

        public func format(_ date: Date) -> String {
            let iso = FileNamer.isoDate(date)
            switch self {
            case .day: return iso
            case .compactDay: return iso.replacing("-", with: "")
            case .month: return String(iso.prefix(7))
            }
        }
    }

    public enum DateSource: String, Equatable, Sendable, Codable, CaseIterable {
        /// The date printed on the document, or the day of the scan when none was found.
        case document
        case scan
    }

    public var datePosition: DatePosition
    public var dateStyle: DateStyle
    public var dateSource: DateSource
    public var separator: Separator
    public var lowercase: Bool

    public init(datePosition: DatePosition = .none, dateStyle: DateStyle = .day, dateSource: DateSource = .document, separator: Separator = .space, lowercase: Bool = false) {
        self.datePosition = datePosition
        self.dateStyle = dateStyle
        self.dateSource = dateSource
        self.separator = separator
        self.lowercase = lowercase
    }

    private enum CodingKeys: String, CodingKey {
        case datePosition, dateStyle, dateSource, separator, lowercase, datePrefix
    }

    /// Missing or unknown values keep their default; the former "date first" switch becomes a date at the start.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        if let position = try? container.decode(DatePosition.self, forKey: .datePosition) {
            datePosition = position
        } else if (try? container.decode(Bool.self, forKey: .datePrefix)) == true {
            datePosition = .start
        }
        dateStyle = (try? container.decode(DateStyle.self, forKey: .dateStyle)) ?? dateStyle
        dateSource = (try? container.decode(DateSource.self, forKey: .dateSource)) ?? dateSource
        separator = (try? container.decode(Separator.self, forKey: .separator)) ?? separator
        lowercase = (try? container.decode(Bool.self, forKey: .lowercase)) ?? lowercase
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(datePosition, forKey: .datePosition)
        try container.encode(dateStyle, forKey: .dateStyle)
        try container.encode(dateSource, forKey: .dateSource)
        try container.encode(separator, forKey: .separator)
        try container.encode(lowercase, forKey: .lowercase)
    }

    /// With dashes or underscores, any run of characters other than letters and digits becomes one separator.
    /// A name that already starts or ends with the date does not get it twice; without a date in the format, it stays where it is.
    public func fileName(name: String, documentDate: Date?, scanDate: Date) -> String {
        let date = dateSource == .document ? documentDate ?? scanDate : scanDate
        let stamp = dateStyle.format(date)
        var rest = name.trimmingCharacters(in: .whitespaces)
        var position = datePosition
        for written in Set([stamp, FileNamer.isoDate(date)]) {
            if rest.hasPrefix(written) {
                rest = String(rest.dropFirst(written.count))
                if position == .none { position = .start }
            } else if rest.hasSuffix(written) {
                rest = String(rest.dropLast(written.count))
                if position == .none { position = .end }
            }
        }
        var words = separator == .space
            ? rest.split(whereSeparator: \.isWhitespace).map(String.init)
            : rest.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        if lowercase { words = words.map { $0.lowercased() } }
        switch position {
        case .none: break
        case .start: words.insert(stamp, at: 0)
        case .end: words.append(stamp)
        }
        return FileNamer().finalName(words.joined(separator: separator.character), fallback: stamp)
    }
}
