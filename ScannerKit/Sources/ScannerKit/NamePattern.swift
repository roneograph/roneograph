import Foundation

/// A name the user gave to a document, kept so the next document from the same issuer gets it too:
/// the parts that match the document's date or number follow the next document, the rest is kept as typed.
/// "Lumen electricity October" on a bill dated November 12 becomes "Lumen electricity November" on the next bill.
public struct NamePattern: Equatable, Sendable, Codable {
    public enum Part: Equatable, Sendable, Codable {
        case text(String)
        case number
        /// `months` moves the date before writing it, -1 for a name that gives the month before the document's.
        case date(DateStyle, months: Int)
    }

    public enum DateStyle: Equatable, Sendable, Codable {
        /// 2026-11-12
        case day
        /// 2026-11
        case month
        /// 2026
        case year
        /// November, novembre, Nov.
        case monthName(locale: String, short: Bool, letterCase: LetterCase)
    }

    public enum LetterCase: String, Equatable, Sendable, Codable {
        case lower, upper, capitalized
    }

    public let parts: [Part]

    /// Finds in the name what comes from the document, so it can follow the next one.
    public init(name: String, details: DocumentDetails, date: Date) {
        let tokens = Self.tokens(of: name)
        let monthOffset = tokens.lazy.compactMap { Self.monthName($0, date: date)?.months }.first
        parts = tokens.map { token in
            guard !token.allSatisfy(\.isWhitespace) else { return .text(token) }
            if let number = details.number, token.caseInsensitiveCompare(number) == .orderedSame { return .number }
            if token.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil, token == Self.iso(date, months: 0) { return .date(.day, months: 0) }
            if token.wholeMatch(of: /\d{4}-\d{2}/) != nil, let months = [0, -1].first(where: { token == String(Self.iso(date, months: $0).prefix(7)) }) {
                return .date(.month, months: months)
            }
            if token.wholeMatch(of: /\d{4}/) != nil, let months = [monthOffset ?? 0, 0, -12].first(where: { token == String(Self.iso(date, months: $0).prefix(4)) }) {
                return .date(.year, months: months)
            }
            if let match = Self.monthName(token, date: date) { return .date(match.style, months: match.months) }
            return .text(token)
        }
    }

    /// The name for another document, with its own date and number; a missing number goes away with the space before it.
    public func name(details: DocumentDetails, date: Date) -> String {
        var result = ""
        for part in parts {
            switch part {
            case .text(let text): result += text
            case .number:
                if let number = details.number { result += number } else { result = String(result.reversed().drop(while: \.isWhitespace).reversed()) }
            case .date(let style, let months): result += Self.format(date, style: style, months: months)
            }
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// True when some of the name follows the next document instead of being kept as typed.
    public var follows: (date: Bool, number: Bool) {
        (parts.contains { if case .date = $0 { true } else { false } }, parts.contains(.number))
    }

    /// Words and the spaces between them, with punctuation around a word kept apart from it.
    private static func tokens(of name: String) -> [String] {
        var tokens: [String] = []
        for match in name.matches(of: /\s+|[^\s]+/) {
            let token = String(match.output)
            guard !token.allSatisfy(\.isWhitespace) else {
                tokens.append(token)
                continue
            }
            let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "(),;:!?\"'«»[]"))
            guard !trimmed.isEmpty, let range = token.range(of: trimmed) else {
                tokens.append(token)
                continue
            }
            if range.lowerBound > token.startIndex { tokens.append(String(token[..<range.lowerBound])) }
            tokens.append(trimmed)
            if range.upperBound < token.endIndex { tokens.append(String(token[range.upperBound...])) }
        }
        return tokens
    }

    /// The user's language first, then English, when a month is written the same in several languages.
    private static let locales = ([Locale.current.identifier] + ["en_US", "fr_FR", "de_DE", "es_ES", "it_IT"]).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

    private static func monthName(_ token: String, date: Date) -> (style: DateStyle, months: Int)? {
        let folded = fold(token)
        guard folded.count >= 3, folded.allSatisfy(\.isLetter) else { return nil }
        for months in [0, -1] {
            let month = calendar.component(.month, from: shifted(date, months: months))
            for locale in locales {
                let symbols = symbols(locale)
                for short in [false, true] where fold((short ? symbols.short : symbols.full)[month - 1]) == folded {
                    return (.monthName(locale: locale, short: short, letterCase: letterCase(of: token)), months)
                }
            }
        }
        return nil
    }

    private static func format(_ date: Date, style: DateStyle, months: Int) -> String {
        let iso = iso(date, months: months)
        switch style {
        case .day: return iso
        case .month: return String(iso.prefix(7))
        case .year: return String(iso.prefix(4))
        case .monthName(let locale, let short, let letterCase):
            let symbols = symbols(locale)
            let name = (short ? symbols.short : symbols.full)[calendar.component(.month, from: shifted(date, months: months)) - 1]
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            switch letterCase {
            case .lower: return name.lowercased()
            case .upper: return name.uppercased()
            case .capitalized: return name.prefix(1).uppercased() + name.dropFirst().lowercased()
            }
        }
    }

    private static func symbols(_ locale: String) -> (full: [String], short: [String]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        return (calendar.standaloneMonthSymbols, calendar.shortStandaloneMonthSymbols)
    }

    private static func letterCase(of token: String) -> LetterCase {
        if token == token.uppercased(), token.count > 1 { return .upper }
        if token.first?.isUppercase == true { return .capitalized }
        return .lower
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    private static func shifted(_ date: Date, months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    private static func iso(_ date: Date, months: Int) -> String {
        FileNamer.isoDate(shifted(date, months: months))
    }
}
