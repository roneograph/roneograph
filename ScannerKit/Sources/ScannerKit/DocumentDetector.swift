import CoreGraphics
import CryptoKit
import Foundation
import NaturalLanguage

/// Reads the details of a document from the text of its first page, with rules only: the same page always gives the same details.
public struct DocumentDetector: Sendable {
    /// Reads 03/04/2026 as March 4 instead of April 3.
    public var monthFirst: Bool

    public init(monthFirst: Bool = Locale.current.region == .unitedStates) {
        self.monthFirst = monthFirst
    }

    /// `ownLines` holds the fingerprints of lines known to be the user's own name and address, never taken as the issuer.
    /// `aspectRatio` is the width over the height of the page, when known: narrow pages are often receipts.
    public func detect(lines: [TextLine], ownLines: Set<String> = [], aspectRatio: CGFloat? = nil) -> DetectedDocument {
        let page = Page(lines: lines, ownLines: ownLines)
        let kind = Self.kind(of: page, aspectRatio: aspectRatio)
        let type = Self.type(in: page, kind: kind)
        let evidence = IssuerEvidence(page: page)
        let candidates = Self.issuerCandidates(in: page, clues: kind.clues)
        let issuer = Self.issuer(among: candidates.filter { !$0.isOwn }, page: page, evidence: evidence)
        let details = DocumentDetails(
            category: kind.category,
            issuer: issuer,
            date: date(in: page),
            number: Self.number(in: page, kind: kind, type: type)
        )
        let keys = evidence.keys(for: issuer)
        return DetectedDocument(
            details: details,
            parts: SuggestedParts(type: type?.word, issuer: type?.isHeading == true ? nil : issuer, number: details.number),
            issuerKeys: keys + (issuer.map { [Self.folded($0).split(whereSeparator: \.isWhitespace).joined(separator: " ")] } ?? []),
            issuerEvidence: keys,
            headerLines: candidates.map { Self.fingerprint($0.text) }
        )
    }

    /// A short, stable fingerprint of a line, so lines can be recognized without keeping their text.
    public static func fingerprint(_ text: String) -> String {
        let folded = folded(Substring(text)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return SHA256.hash(data: Data(folded.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func folded<S: StringProtocol>(_ word: S) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "#°º")))
    }

    // MARK: Page

    struct Token {
        var text: Substring
        /// Folded, without surrounding punctuation; number markers (n°, nº, no, nr, #) all become "n°".
        var key: String

        static let markers: Set<String> = ["n°", "nº", "no", "n", "nr", "nro", "num", "#", "n.º", "n.°"]

        init(_ text: Substring) {
            self.text = text
            let key = DocumentDetector.folded(text.replacing("’", with: "'"))
            self.key = Self.markers.contains(key) ? "n°" : key
        }
    }

    struct Line {
        var text: String
        var frame: CGRect
        var confidence: Float
        var tokens: [Token]
        /// Folded text, for dates.
        var folded: String
        var isOwn: Bool

        var words: [Token] { tokens.filter { !$0.key.isEmpty } }
    }

    struct Page {
        var lines: [Line]
        /// The usual height of a line of body text.
        var bodyHeight: CGFloat

        init(lines: [TextLine], ownLines: Set<String>) {
            self.lines = lines.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }.map { line in
                Line(
                    text: line.text,
                    frame: line.frame,
                    confidence: line.confidence,
                    tokens: line.text.split(whereSeparator: \.isWhitespace).map(Token.init),
                    folded: line.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).replacing("’", with: "'"),
                    isOwn: !ownLines.isEmpty && ownLines.contains(DocumentDetector.fingerprint(line.text))
                )
            }
            let heights = lines.map(\.frame.height).sorted()
            bodyHeight = heights.isEmpty ? 0.01 : heights[heights.count / 2]
        }

        func isLarge(_ line: Line) -> Bool {
            line.frame.height >= bodyHeight * 1.4
        }

        /// The nearest line on the same row, to the left or to the right.
        func neighbor(of line: Line, toTheRight: Bool) -> Line? {
            lines.filter { other in
                abs(other.frame.midY - line.frame.midY) < max(other.frame.height, line.frame.height) * 0.5
                    && (toTheRight ? other.frame.minX >= line.frame.maxX - 0.01 : other.frame.maxX <= line.frame.minX + 0.01)
            }.min { abs($0.frame.minX - line.frame.minX) < abs($1.frame.minX - line.frame.minX) }
        }
    }

    // MARK: Phrases

    struct Phrase: Sendable {
        var tokens: [String]
        /// The first token may end a longer word.
        var isSuffix: Bool
        var isAnchored: Bool

        init(_ text: String) {
            var text = Substring(text)
            isAnchored = text.hasPrefix("^")
            if isAnchored { text = text.dropFirst() }
            isSuffix = text.hasPrefix("*")
            if isSuffix { text = text.dropFirst() }
            tokens = text.split(whereSeparator: \.isWhitespace).map { Token($0).key }
        }

        func matches(_ tokens: [Token], at index: Int) -> Bool {
            guard index + self.tokens.count <= tokens.count else { return false }
            for (offset, key) in self.tokens.enumerated() {
                let candidate = tokens[index + offset].key
                if offset == 0 && isSuffix ? !(candidate.hasSuffix(key) && candidate.count > key.count) : candidate != key { return false }
            }
            return true
        }
    }

    /// Phrases indexed by their first word, longer phrases first and exact words before word endings.
    struct Phrases<Tag: Sendable>: Sendable {
        private var byFirstWord: [String: [(phrase: Phrase, tag: Tag, rank: Int)]] = [:]
        private var suffixes: [(phrase: Phrase, tag: Tag, rank: Int)] = []

        init(_ phrases: [(Phrase, Tag)]) {
            let ranked = phrases.enumerated().sorted { a, b in
                (a.element.0.tokens.count, a.element.0.isSuffix ? 0 : 1, a.element.0.tokens.joined().count, -a.offset)
                    > (b.element.0.tokens.count, b.element.0.isSuffix ? 0 : 1, b.element.0.tokens.joined().count, -b.offset)
            }.map(\.element)
            for (rank, (phrase, tag)) in ranked.enumerated() {
                if phrase.isSuffix {
                    suffixes.append((phrase, tag, rank))
                } else if let first = phrase.tokens.first {
                    byFirstWord[first, default: []].append((phrase, tag, rank))
                }
            }
        }

        /// Where each phrase was found on a line, longer phrases first: "attestation d'assurance" hides "attestation".
        func matches(in line: Line) -> [(range: Range<Int>, tag: Tag)] {
            let firstWord = line.tokens.firstIndex { !$0.key.isEmpty } ?? 0
            var candidates: [(range: Range<Int>, tag: Tag, rank: Int)] = []
            for (index, token) in line.tokens.enumerated() where !token.key.isEmpty {
                let possible = (byFirstWord[token.key] ?? []) + suffixes.filter { token.key.hasSuffix($0.phrase.tokens[0]) }
                for (phrase, tag, rank) in possible where (!phrase.isAnchored || index == firstWord) && phrase.matches(line.tokens, at: index) {
                    candidates.append((index..<(index + phrase.tokens.count), tag, rank))
                }
            }
            var found: [(range: Range<Int>, tag: Tag)] = []
            for candidate in candidates.sorted(by: { $0.rank < $1.rank }) where !found.contains(where: { $0.range.overlaps(candidate.range) }) {
                found.append((candidate.range, candidate.tag))
            }
            return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
        }
    }

    // MARK: Category

    enum Evidence: Sendable {
        case title(weight: Double), label, letter
    }

    struct Clue: Sendable {
        var category: DocumentCategory?
        var evidence: Evidence
        /// Also found in the names of organizations, such as "Assurances".
        var isInNames = false
        var phrase: Int
    }

    private static let clues: Phrases<Clue> = {
        var phrases: [(Phrase, Clue)] = []
        for entry in DocumentVocabulary.entries {
            for title in entry.titles { phrases.append((Phrase(title), Clue(category: entry.category, evidence: .title(weight: entry.category == nil ? 0 : 3), phrase: phrases.count))) }
            for title in entry.weakTitles { phrases.append((Phrase(title), Clue(category: entry.category, evidence: .title(weight: 2), phrase: phrases.count))) }
            for word in entry.nameWords { phrases.append((Phrase(word), Clue(category: entry.category, evidence: .title(weight: 2), isInNames: true, phrase: phrases.count))) }
            for label in entry.labels { phrases.append((Phrase(label), Clue(category: entry.category, evidence: .label, phrase: phrases.count))) }
        }
        for phrase in DocumentVocabulary.letter { phrases.append((Phrase(phrase), Clue(category: .letter, evidence: .letter, phrase: phrases.count))) }
        return Phrases(phrases)
    }()

    struct Kind {
        var category: DocumentCategory
        /// The clues found on each line.
        var clues: [[(range: Range<Int>, tag: Clue)]]
    }

    static let threshold = 3.0

    /// Scores every category over the page: titles weigh more than labels, more so in big letters near the top.
    static func kind(of page: Page, aspectRatio: CGFloat?) -> Kind {
        let found = page.lines.map(clues.matches)
        var best: [Int: (category: DocumentCategory, weight: Double)] = [:]
        for (line, matches) in zip(page.lines, found) {
            for match in matches {
                guard let category = match.tag.category else { continue }
                let weight = Self.weight(of: match.tag.evidence, on: line, page: page)
                if weight > best[match.tag.phrase]?.weight ?? 0 { best[match.tag.phrase] = (category, weight) }
            }
        }
        var scores: [DocumentCategory: Double] = [:]
        for (_, (category, weight)) in best.sorted(by: { $0.key < $1.key }) { scores[category, default: 0] += weight }
        if let aspectRatio, aspectRatio < 0.5 { scores[.receipt, default: 0] += 2 }

        let ranked = DocumentCategory.builtIn.filter { $0 != .letter && $0 != .other }.map { ($0, scores[$0] ?? 0) }
        let winner = ranked.max { $0.1 < $1.1 }
        let category: DocumentCategory = if let winner, winner.1 >= threshold { winner.0 } else if scores[.letter] ?? 0 >= threshold { .letter } else { .other }
        return Kind(category: category, clues: found)
    }

    private static func weight(of evidence: Evidence, on line: Line, page: Page) -> Double {
        switch evidence {
        case .label: 1
        case .letter: 2
        case let .title(weight) where isTitleLike(line): weight * (page.isLarge(line) ? 2 : 1) * (line.frame.minY < 0.4 ? 1.5 : 1)
        case .title: 1
        }
    }

    /// A short line that is not an item of a list.
    static func isTitleLike(_ line: Line) -> Bool {
        let first = line.tokens.first.map { String($0.text) } ?? ""
        return line.words.count <= 7 && !["-", "•", "–", "*", "·"].contains(first)
    }

    // MARK: Type

    struct DocumentType {
        var word: String
        var isHeading: Bool
        var line: Int
        var range: Range<Int>
    }

    /// The title that gave the category, or the whole heading it starts.
    static func type(in page: Page, kind: Kind) -> DocumentType? {
        var best: (type: DocumentType, weight: Double)?
        for (index, line) in page.lines.enumerated() where isTitleLike(line) {
            for match in kind.clues[index] {
                guard case .title = match.tag.evidence else { continue }
                let fits = match.tag.category == kind.category || (match.tag.category == nil && [.other, .letter].contains(kind.category))
                guard fits else { continue }
                let weight = match.tag.category == nil ? 1 : Self.weight(of: match.tag.evidence, on: line, page: page)
                guard weight > best?.weight ?? 0 else { continue }
                let words = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
                let firstWord = line.tokens.firstIndex { !$0.key.isEmpty } ?? 0
                let isHeading = match.range.lowerBound == firstWord && (2...6).contains(words.count) && !line.text.contains(where: \.isNumber) && !line.text.contains(":")
                let word: String
                if isHeading {
                    word = titleCased(words, capitalizeAll: false).trimmingCharacters(in: .punctuationCharacters)
                } else {
                    let text = line.tokens[match.range].map(\.text).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
                    word = text.prefix(1).uppercased() + text.dropFirst().lowercased()
                }
                best = (DocumentType(word: word, isHeading: isHeading, line: index, range: match.range), weight)
            }
        }
        return best?.type
    }

    private static let smallWords: Set<String> = ["de", "du", "des", "la", "le", "les", "et", "of", "the", "and", "for", "von", "der", "und", "di", "del", "della", "delle", "y", "il"]

    /// Calms down text in capitals: "OFFICE DU TOURISME" becomes "Office du Tourisme", or "Office du tourisme" without `capitalizeAll`.
    static func titleCased(_ words: [String], capitalizeAll: Bool = true) -> String {
        let shouting = words.joined().filter(\.isLetter).allSatisfy(\.isUppercase)
        guard shouting else { return words.joined(separator: " ") }
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            let capitalize = index == 0 || (capitalizeAll && !smallWords.contains(lower))
            return capitalize ? lower.prefix(1).uppercased() + lower.dropFirst() : lower
        }.joined(separator: " ")
    }

    // MARK: Number

    private static let numberLabels: [DocumentCategory?: Phrases<Bool>] = Dictionary(
        DocumentVocabulary.entries.map { ($0.category, Phrases($0.numberLabels.map { (Phrase($0), true) })) },
        uniquingKeysWith: { first, _ in first }
    )

    /// The reference next to a label of the category, after the title, or next to a customer or file reference.
    static func number(in page: Page, kind: Kind, type: DocumentType?) -> String? {
        let labels = numberLabels[kind.category] ?? Phrases([])
        for line in page.lines where !line.isOwn {
            for match in labels.matches(in: line) {
                if let value = value(after: match.range.upperBound, in: line, page: page) { return value }
            }
        }
        if let type, let value = value(after: type.range.upperBound, in: page.lines[type.line], page: page, sameLineOnly: true) {
            return value
        }
        for line in page.lines where !line.isOwn {
            for match in (numberLabels[nil] ?? Phrases([])).matches(in: line) {
                if let value = value(after: match.range.upperBound, in: line, page: page) { return value }
            }
        }
        return nil
    }

    private static let skippedBeforeValue: Set<String> = ["", "n°", "de", "du", "d'", "number", "numero", "nummer", "nr", "del", "di"]

    private static func value(after index: Int, in line: Line, page: Page, sameLineOnly: Bool = false) -> String? {
        var tokens = line.tokens[index...].drop { skippedBeforeValue.contains($0.key) }
        if tokens.isEmpty, !sameLineOnly, let next = page.neighbor(of: line, toTheRight: true) {
            tokens = next.tokens[...].drop { skippedBeforeValue.contains($0.key) }
        }
        var parts: [String] = []
        for token in tokens {
            let text = token.text.trimmingCharacters(in: CharacterSet(charactersIn: ",;.:()"))
            guard text.contains(where: \.isNumber), text.first?.isLetter == true || text.first?.isNumber == true,
                  text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "/-._".contains($0)) }), !isDate(text) else { break }
            parts.append(text)
        }
        let value = parts.joined(separator: " ")
        let isYear = value.count == 4 && Int(value).map { (1990...2100).contains($0) } == true
        return value.filter { $0.isLetter || $0.isNumber }.count >= 3 && !isYear ? value : nil
    }

    private static func isDate(_ text: String) -> Bool {
        !dateMatches(in: text, monthFirst: false).isEmpty
    }

    // MARK: Issuer

    /// Name-like lines in the header, own lines included so they can be learned.
    static func issuerCandidates(in page: Page, clues: [[(range: Range<Int>, tag: Clue)]]) -> [Line] {
        page.lines.enumerated().filter { index, line in
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let letters = text.filter(\.isLetter).count
            let digits = text.filter(\.isNumber).count
            let inHeader = (line.frame.minY < 0.3 && line.frame.minX < 0.5) || (line.frame.minY < 0.12 && page.isLarge(line))
            guard inHeader, line.confidence > 0.5, (3...60).contains(text.count), line.words.count <= 8, Double(letters) >= Double(text.count) * 0.6, digits <= 2,
                  !(text.first?.isNumber ?? false), !text.contains("@"), !text.contains(":"), !text.lowercased().contains("www."), IssuerEvidence.domains(in: text).isEmpty,
                  let first = line.words.first else { return false }
            if DocumentVocabulary.recipientPrefixes.contains(first.key.replacing(".", with: "")) { return false }
            let isAddress = line.words.contains { DocumentVocabulary.streetWords.contains($0.key.replacing(".", with: "")) } || postcode.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            if isAddress && !page.isLarge(line) { return false }
            return !clues[index].contains { match in
                switch match.tag.evidence {
                case .title: !match.tag.isInNames
                case .letter: true
                case .label: match.range.count == line.words.count
                }
            }
        }.map(\.element)
    }

    /// The most prominent candidate, strengthened by legal forms, domains and company identifiers, and by organization names when that is not enough.
    static func issuer(among candidates: [Line], page: Page, evidence: IssuerEvidence) -> String? {
        var scored = candidates.map { line -> (line: Line, score: Double, isLikely: Bool) in
            var score = 2 * min(line.frame.height / page.bodyHeight, 3) + (0.3 - line.frame.minY) * 5
            let name = issuerName(of: line)
            let letters = Self.letters(name)
            let below = page.lines.filter { $0.frame.minY > line.frame.minY && $0.frame.minY - line.frame.maxY < line.frame.height * 2.5 }
            let bonuses: [Double] = [
                line.words.contains(where: isLegalForm) ? 3 : 0,
                evidence.domains.contains { domain($0.domain, matches: name) } ? 3 : 0,
                evidence.legalNames.contains { $0.line != line.text && Self.letters($0.name) == letters } ? 4 : 0,
                line.words.first.map { DocumentVocabulary.professionalTitles.contains($0.key.replacing(".", with: "")) } == true ? 2 : 0,
                below.prefix(2).contains { !IssuerEvidence.identifiers(in: $0.text).isEmpty || $0.words.first.map(isLegalForm) == true } ? 2 : 0,
            ]
            return (line, score + bonuses.reduce(0, +), bonuses.contains { $0 > 0 } || page.isLarge(line))
        }
        let ranked = scored.map(\.score).sorted(by: >)
        if ranked.count >= 2, ranked[0] - ranked[1] < 1 {
            let organizations = Self.organizations(in: page)
            for index in scored.indices {
                let letters = Self.letters(issuerName(of: scored[index].line))
                if organizations.contains(where: { $0.contains(letters) && letters.count * 3 >= $0.count * 2 }) { scored[index].score += 1 }
            }
        }
        let legalName = evidence.legalNames.first { name in
            name.isInHeaderOrFooter || name.hasIdentifier || evidence.domains.contains { domain($0.domain, matches: name.name) }
        }
        guard let best = scored.max(by: { $0.score < $1.score }), best.isLikely || legalName == nil else { return legalName?.name }
        return issuerName(of: best.line)
    }

    /// The name on a line, without the legal form or what follows a separator.
    static func issuerName(of line: Line) -> String {
        var words: [String] = []
        for token in line.tokens {
            if ["·", "|", "-", "–", "—", "("].contains(token.text) || token.text.hasPrefix("(") { break }
            words.append(String(token.text))
        }
        while let last = words.last, isLegalForm(Token(Substring(last))) || last.allSatisfy({ $0.isPunctuation }) {
            words.removeLast()
        }
        if let last = words.last, last.hasSuffix(",") { words[words.count - 1] = String(last.dropLast()) }
        return titleCased(Array(words.prefix(5))).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces).subtracting(CharacterSet(charactersIn: ".")))
    }

    static func isLegalForm(_ token: Token) -> Bool {
        DocumentVocabulary.legalForms.contains(token.key.replacing(".", with: "")) && token.text.contains(where: \.isUppercase) && token.text.count <= 7
    }

    /// Letters only, folded, for comparing names with domains: "Lindgrün" gives "lindgrun".
    static func letters(_ text: String) -> String {
        folded(text).filter(\.isLetter)
    }

    /// Whether a domain is made of the name, or of one of its longer words: "maler-kessler.de" for "Malerbetrieb Kessler", "lindgruen.de" for "Lindgrün".
    static func domain(_ domain: String, matches name: String) -> Bool {
        let spellings = Set([letters(name), letters(name.lowercased().replacing("ä", with: "ae").replacing("ö", with: "oe").replacing("ü", with: "ue").replacing("ß", with: "ss"))])
        guard let shortest = spellings.map(\.count).min(), shortest >= 3 else { return false }
        let stem = domain.split(separator: ".").first.map(String.init) ?? domain
        let parts = [stem.filter(\.isLetter)] + stem.split(separator: "-").map(String.init).filter { $0.count >= 5 }
        return parts.contains { part in
            part.count >= 4 && spellings.contains { $0.contains(part) || ($0.count >= 5 && part.contains($0)) }
        }
    }

    // MARK: Date

    struct FoundDate {
        var date: Date
        var score: Int
    }

    func date(in page: Page) -> Date? {
        var best: FoundDate?
        for line in page.lines where !line.isOwn {
            for found in dates(on: line, page: page) where found.score > best?.score ?? 0 {
                best = found
            }
        }
        return best?.date
    }

    private func dates(on line: Line, page: Page) -> [FoundDate] {
        let text = line.folded
        let matches = Self.dateMatches(in: text, monthFirst: monthFirst)
        return matches.enumerated().compactMap { index, match in
            let previousEnd = index > 0 ? matches[index - 1].range.upperBound : text.startIndex
            let between = Self.trimmed(text[previousEnd..<match.range.lowerBound])
            let isPeriodEnd = index > 0 && DocumentVocabulary.periodEnds.contains(between)
            let next = index + 1 < matches.count ? Self.trimmed(text[match.range.upperBound..<matches[index + 1].range.lowerBound]) : nil
            if let next, DocumentVocabulary.periodEnds.contains(next) { return nil }

            var label = Self.trimmed(text[text.startIndex..<(isPeriodEnd ? matches[0].range.lowerBound : match.range.lowerBound)])
            if label.isEmpty, let neighbor = page.neighbor(of: line, toTheRight: false) {
                label = Self.trimmed(Substring(neighbor.folded))
            }
            if Self.contains(Self.otherDateLabels, in: label) { return nil }
            let score: Int
            if Self.contains(Self.issueDateLabels, in: label) {
                score = 100
            } else if Self.placeAndDate.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)) != nil {
                score = 90
            } else if let last = label.split(separator: " ").last, DocumentVocabulary.dateLabels.contains(String(last)) {
                score = 80
            } else if isPeriodEnd {
                score = 50
            } else {
                score = line.frame.minY < 0.3 ? 60 : 30
            }
            return FoundDate(date: match.date, score: score)
        }
    }

    /// "Lyon, le", "Leipzig, den", "En Madrid, a", "Bologna,".
    private static let placeAndDate = try! NSRegularExpression(pattern: #"^(fait a |en )?[\p{L}' \-]{2,30}, ?(le|den|a|li|il)?$"#)
    private static let postcode = try! NSRegularExpression(pattern: #"\b[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2}\b"#)

    private static func trimmed(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters).subtracting(CharacterSet(charactersIn: "-–")))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func words(_ text: String) -> String {
        " " + text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).split(whereSeparator: { !$0.isLetter && !$0.isNumber && !"'()".contains($0) }).joined(separator: " ") + " "
    }

    private static let issueDateLabels = DocumentVocabulary.issueDateLabels.map(words)
    private static let otherDateLabels = DocumentVocabulary.otherDateLabels.map(words)

    /// Whether one of the phrases, prepared with `words`, appears as whole words in the text.
    static func contains(_ phrases: [String], in text: String) -> Bool {
        let text = words(text)
        return phrases.contains { text.contains($0) }
    }

    struct DateMatch {
        var range: Range<String.Index>
        var date: Date
    }

    private static let isoDate = try! NSRegularExpression(pattern: #"(?<!\d)(\d{4})[\-/.](\d{1,2})[\-/.](\d{1,2})(?!\d)"#)
    private static let numericDate = try! NSRegularExpression(pattern: #"(?<![\d.,])(\d{1,2})([/.\-])(\d{1,2})[/.\-](\d{4}|\d{2})(?![\d,]|\.\d)"#)
    private static let dayMonthDate = try! NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})(?:er|st|nd|rd|th|º|°)?\.?\s+(?:de\s+)?(\p{L}+)\.?,?\s+(?:de\s+|del\s+)?(\d{4})(?!\d)"#)
    private static let monthDayDate = try! NSRegularExpression(pattern: #"\b(\p{L}+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})(?!\d)"#)

    /// Every date written on the folded text, in order: 2026-03-14, 14/03/2026, 14.03.26, 14 mars 2026, March 14, 2026, 14 de marzo de 2026.
    static func dateMatches(in text: String, monthFirst: Bool) -> [DateMatch] {
        guard text.count(where: \.isNumber) >= 4 else { return [] }
        var found: [DateMatch] = []
        let whole = NSRange(text.startIndex..., in: text)
        func each(_ expression: NSRegularExpression, _ body: ([String]) -> Date?) {
            for result in expression.matches(in: text, range: whole) {
                guard let range = Range(result.range, in: text), !found.contains(where: { $0.range.overlaps(range) }) else { continue }
                let groups = (1..<result.numberOfRanges).map { Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
                if let date = body(groups) { found.append(DateMatch(range: range, date: date)) }
            }
        }
        each(isoDate) { groups in date(Int(groups[0])!, Int(groups[1])!, Int(groups[2])!) }
        each(numericDate) { groups in
            let (a, b) = (Int(groups[0])!, Int(groups[2])!)
            var year = Int(groups[3])!
            if groups[3].count == 2 {
                guard groups[1] != "-" else { return nil }
                year += 2000
            }
            let (day, month) = a > 12 ? (a, b) : b > 12 ? (b, a) : monthFirst ? (b, a) : (a, b)
            return date(year, month, day)
        }
        each(dayMonthDate) { groups in DocumentVocabulary.months[groups[1]].flatMap { date(Int(groups[2])!, $0, Int(groups[0])!) } }
        each(monthDayDate) { groups in DocumentVocabulary.months[groups[0]].flatMap { date(Int(groups[2])!, $0, Int(groups[1])!) } }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        guard (1990...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }
}
