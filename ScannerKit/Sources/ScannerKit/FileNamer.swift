import CoreGraphics
import Foundation

/// A line of text read on a page, with its frame normalized to the upright page, origin at the top left.
public struct TextLine: Equatable, Sendable {
    public var text: String
    public var frame: CGRect
    /// Recognition confidence, from 0 to 1.
    public var confidence: Float

    public init(text: String, frame: CGRect, confidence: Float = 1) {
        self.text = text
        self.frame = frame
        self.confidence = confidence
    }
}

/// Names suggested from the text of a page, and the date printed on it.
public struct NameSuggestions: Equatable, Sendable {
    public var names: [String]
    /// Nil when no date was found.
    public var date: Date?

    public init(names: [String], date: Date?) {
        self.names = names
        self.date = date
    }
}

/// Suggests file names from the text of a page and keeps names valid for file systems and mail apps.
public struct FileNamer: Sendable {
    public static let forbidden = Set("/\\:*?\"<>|")
    public var maximumLength = 80
    /// Reads 03/04/2026 as March 4 instead of April 3.
    public var monthFirst: Bool

    public init(monthFirst: Bool = Locale.current.region == .unitedStates) {
        self.monthFirst = monthFirst
    }

    /// Replaces the characters file systems or mail apps reject by a dash, as the user types.
    public func sanitize(_ name: String) -> String {
        var result = String(name.map { Self.forbidden.contains($0) || $0.isNewline ? "-" : $0 }.filter { !$0.unicodeScalars.allSatisfy(\.properties.isDefaultIgnorableCodePoint) })
        while result.hasPrefix(".") { result.removeFirst() }
        return String(result.prefix(maximumLength))
    }

    /// The final name: sanitized, trimmed, never empty.
    public func finalName(_ name: String, fallback: String) -> String {
        let trimmed = sanitize(name).trimmingCharacters(in: .whitespaces).replacing(/\ {2,}/, with: " ")
        return trimmed.isEmpty ? fallback : trimmed
    }

    public func fallback(for date: Date) -> String {
        "Scan \(Self.isoDate(date))"
    }

    /// Up to two names, best first, or the fallback name when the text says nothing useful.
    public func suggestions(lines: [TextLine], date: Date) -> NameSuggestions {
        let lines = lines.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        let type = documentType(in: lines)
        let isHeading = type.map { $0.word.contains(" ") } ?? false
        let issuer = isHeading ? nil : issuer(in: lines)

        let typeAndIssuer = [type?.word, issuer].compactMap { $0 }.joined(separator: " ")
        let typeAndNumber = type.flatMap { type in type.number.map { "\(type.word) \($0)" } }
        let best = issuer == nil ? typeAndNumber ?? type?.word : typeAndIssuer

        var seen = Set<String>()
        let names = [best, typeAndNumber].compactMap { $0 }.map { finalName($0, fallback: "") }.filter { !$0.isEmpty && seen.insert($0).inserted }
        return NameSuggestions(names: names.isEmpty ? [fallback(for: date)] : names, date: self.date(in: lines))
    }

    // MARK: Document type

    struct DocumentType {
        var word: String
        var number: String?
    }

    private static let types: Set<String> = [
        "invoice", "receipt", "quote", "estimate", "contract", "statement", "certificate", "order", "payslip", "prescription", "ticket",
        "facture", "recu", "recepisse", "devis", "contrat", "releve", "certificat", "attestation", "commande", "ordonnance", "avis", "bulletin",
        "rechnung", "quittung", "vertrag", "bescheinigung", "factura", "recibo", "fattura", "ricevuta",
    ]
    private static let numberMarkers: Set<String> = ["n", "no", "nº", "n°", "#", "number", "num", "numero", "nr", ":"]

    private func documentType(in lines: [TextLine]) -> DocumentType? {
        for line in lines {
            let words = line.text.split(whereSeparator: { $0.isWhitespace })
            for (index, word) in words.enumerated() where Self.types.contains(Self.folded(word)) {
                let isHeading = index == 0 && words.count >= 2 && words.count <= 6 && !line.text.contains(where: \.isNumber) && !line.text.contains(":")
                if isHeading {
                    let heading = Self.titleCased(words.map(String.init), capitalizeAll: false)
                    return DocumentType(word: heading.trimmingCharacters(in: .punctuationCharacters), number: nil)
                }
                let display = word.prefix(1).uppercased() + word.dropFirst().lowercased()
                let number = words.dropFirst(index + 1).first { !Self.numberMarkers.contains(Self.folded($0)) }
                    .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                    .flatMap { $0.count >= 3 && $0.contains(where: \.isNumber) ? $0 : nil }
                return DocumentType(word: String(display.trimmingCharacters(in: .punctuationCharacters)), number: number)
            }
        }
        return nil
    }

    // MARK: Issuer

    /// The most prominent name-like line in the top part of the page: big letters, few digits.
    private func issuer(in lines: [TextLine]) -> String? {
        let candidates = lines.filter { line in
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let letters = text.filter(\.isLetter).count
            let digits = text.filter(\.isNumber).count
            let words = text.split(separator: " ").map(Self.folded)
            return line.frame.minY < 0.3 && line.frame.minX < 0.45 && line.confidence > 0.5 && text.count >= 3 && text.count <= 60
                && Double(letters) >= Double(text.count) * 0.6 && digits <= 2 && !(text.first?.isNumber ?? false) && !text.contains("@") && !text.contains(":")
                && !words.contains(where: Self.types.contains)
        }
        guard let best = candidates.max(by: { ($0.frame.height, -$0.frame.minY) < ($1.frame.height, -$1.frame.minY) }) else { return nil }
        let words = best.text.split(separator: " ").prefix(5).map(String.init)
        return Self.titleCased(words).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    private static let smallWords: Set<String> = ["de", "du", "des", "la", "le", "les", "et", "of", "the", "and", "for", "von", "der", "und"]

    /// Calms down text in capitals: "OFFICE DU TOURISME" becomes "Office du Tourisme", or "Office du tourisme" without `capitalizeAll`.
    private static func titleCased(_ words: [String], capitalizeAll: Bool = true) -> String {
        let shouting = words.joined().filter(\.isLetter).allSatisfy(\.isUppercase)
        guard shouting else { return words.joined(separator: " ") }
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            let capitalize = index == 0 || (capitalizeAll && !smallWords.contains(lower))
            return capitalize ? lower.prefix(1).uppercased() + lower.dropFirst() : lower
        }.joined(separator: " ")
    }

    // MARK: Date

    private static let months: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
        "janvier": 1, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11, "decembre": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    func date(in lines: [TextLine]) -> Date? {
        for line in lines {
            let text = Self.folded(Substring(line.text))
            if let match = text.firstMatch(of: /\b(\d{4})-(\d{1,2})-(\d{1,2})\b/), let date = Self.date(Int(match.1)!, Int(match.2)!, Int(match.3)!) {
                return date
            }
            if let match = text.firstMatch(of: /\b(\d{1,2})[\/.](\d{1,2})[\/.](\d{4})\b/) {
                let (a, b, year) = (Int(match.1)!, Int(match.2)!, Int(match.3)!)
                let (day, month) = a > 12 ? (a, b) : b > 12 ? (b, a) : monthFirst ? (b, a) : (a, b)
                if let date = Self.date(year, month, day) { return date }
            }
            if let match = text.firstMatch(of: /\b(\d{1,2})(?:er)? ([a-z]+)\.? (\d{4})\b/), let month = Self.months[String(match.2)], let date = Self.date(Int(match.3)!, month, Int(match.1)!) {
                return date
            }
            if let match = text.firstMatch(of: /\b([a-z]+)\.? (\d{1,2}),? (\d{4})\b/), let month = Self.months[String(match.1)], let date = Self.date(Int(match.3)!, month, Int(match.2)!) {
                return date
            }
        }
        return nil
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        guard (1990...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    public static func isoDate(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    private static func folded<S: StringProtocol>(_ word: S) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "#°º")))
    }
}
