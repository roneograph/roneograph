import Foundation

/// Finds the correspondent or document type of a Paperless-ngx server a name stands for, so an issuer read as "Taxi V7" reuses the "V7" correspondent instead of adding another one.
/// Case, accents, punctuation and legal forms never matter; otherwise, one name must hold the other as a whole sequence of words.
/// It refuses rather than guesses: a name too short to tell, or several objects that could be meant, matches none.
public struct PaperlessMatcher: Sendable {
    /// How far a name may be from the object it stands for.
    public enum Tolerance: Sendable {
        /// Only case, accents, punctuation, legal forms and spaces between words: for a name the user typed, which is otherwise meant as typed.
        case cosmetic
        /// Also one name holding the other: for a name read on a page.
        case related
    }

    private struct Entry: Sendable {
        let object: PaperlessObject
        let words: [String]
    }

    private let entries: [Entry]

    public init(_ objects: [PaperlessObject]) {
        entries = objects.map { Entry(object: $0, words: Self.words($0.name)) }
    }

    public var objects: [PaperlessObject] { entries.map(\.object) }

    /// The object named like `name` whatever its case, else the only one with the same words, else the only one with the same letters once its words are joined;
    /// with a related tolerance, else the only one whose words hold or are held by its words, and among names all held by `name` and nested in one another, the one holding the others.
    public func match(_ name: String, tolerance: Tolerance = .related) -> PaperlessObject? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let lowercased = name.lowercased()
        if let same = entries.first(where: { $0.object.name.trimmingCharacters(in: .whitespaces).lowercased() == lowercased }) { return same.object }
        let words = Self.words(name)
        guard !words.isEmpty else { return nil }
        let equal = entries.filter { $0.words == words }
        if !equal.isEmpty { return equal.count == 1 ? equal[0].object : nil }
        let joined = entries.filter { $0.words.joined() == words.joined() }
        if !joined.isEmpty { return joined.count == 1 ? joined[0].object : nil }
        guard tolerance == .related else { return nil }
        let related = entries.filter { entry in
            guard !entry.words.isEmpty else { return false }
            let (part, whole) = entry.words.count < words.count ? (entry.words, words) : (words, entry.words)
            return Self.isDistinctive(part) && Self.contains(whole, part)
        }
        if related.count == 1 { return related[0].object }
        return Self.widest(related, heldBy: words)?.object
    }

    /// The objects to offer for a typed name, best first: the one it would stand for if read on a page, then the names starting like it, the names with words starting like each of its words,
    /// and the names sharing one of its words.
    public func suggestions(for text: String, limit: Int = 5) -> [PaperlessObject] {
        let words = Self.words(text)
        guard !words.isEmpty else { return [] }
        let matched = match(text, tolerance: .related)
        let typed = words.joined(separator: " ")
        let ranked = entries.compactMap { entry -> (rank: Int, object: PaperlessObject)? in
            if entry.object == matched { return (0, entry.object) }
            if entry.words.joined(separator: " ").hasPrefix(typed) { return (1, entry.object) }
            if words.allSatisfy({ word in entry.words.contains { $0.hasPrefix(word) } }) { return (2, entry.object) }
            if words.contains(where: { word in Self.isDistinctive([word]) && entry.words.contains(word) }) { return (3, entry.object) }
            return nil
        }
        return ranked
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.object.name.localizedStandardCompare($1.object.name) == .orderedAscending }
            .prefix(limit)
            .map(\.object)
    }

    /// The name holding every other one, when they are all held by `words`, as "Fernwood Cloud Services" over "Fernwood" for "Fernwood Cloud Services EMEA";
    /// nil when two of them are not nested, or when one holds `words`.
    private static func widest(_ entries: [Entry], heldBy words: [String]) -> Entry? {
        guard entries.allSatisfy({ $0.words.count < words.count }), let widest = entries.max(by: { $0.words.count < $1.words.count }) else { return nil }
        let others = entries.filter { $0.object != widest.object }
        guard others.allSatisfy({ $0.words != widest.words && contains(widest.words, $0.words) }) else { return nil }
        return widest
    }

    static let legalForms = OwnerMatcher.legalForms.union(DocumentVocabulary.legalForms)

    /// Folded words without punctuation nor legal forms, unless the name is only legal forms.
    static func words(_ name: String) -> [String] {
        let words = OwnerMatcher.words(name)
        let core = words.filter { !legalForms.contains($0) }
        return core.isEmpty ? words : core
    }

    /// Long enough not to be found by chance in another name: three letters or digits, or two mixing a letter and a digit, as "V7";
    /// never only generic words such as "Group" or "and".
    static func isDistinctive(_ words: [String]) -> Bool {
        guard !words.allSatisfy({ OwnerMatcher.genericWords.contains($0) || OwnerMatcher.connectors.contains($0) }) else { return false }
        let text = words.joined()
        return text.count >= 3 || (text.count == 2 && text.contains(where: \.isNumber) && text.contains(where: \.isLetter))
    }

    /// Whether `part` is a run of consecutive words of `whole`.
    static func contains(_ whole: [String], _ part: [String]) -> Bool {
        guard !part.isEmpty, part.count <= whole.count else { return false }
        return (0...(whole.count - part.count)).contains { Array(whole[$0..<($0 + part.count)]) == part }
    }
}
