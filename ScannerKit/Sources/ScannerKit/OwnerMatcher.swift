import CoreGraphics
import Foundation

/// What on the page told its owner.
public enum OwnerClue: String, Sendable, Codable {
    case name, address
}

public struct RecognizedOwner: Equatable, Sendable {
    public var id: UUID
    public var clue: OwnerClue

    public init(id: UUID, clue: OwnerClue) {
        self.id = id
        self.clue = clue
    }
}

/// Tells which owner a page is addressed to from the names and addresses of the owners printed in its top half, where mail puts the recipient.
/// Case, accents, punctuation and word order never matter.
public struct OwnerMatcher: Sendable {
    public struct Match: Equatable, Sendable {
        public var owner: RecognizedOwner?
        /// The indices of the lines that are an owner's name or part of its address: never the issuer.
        public var ownerLines: Set<Int>

        public init(owner: RecognizedOwner? = nil, ownerLines: Set<Int> = []) {
            self.owner = owner
            self.ownerLines = ownerLines
        }
    }

    private struct Entry: Sendable {
        var id: UUID
        var names: [OwnerName]
        var addresses: [[String]]
    }

    private let entries: [Entry]
    private let defaultOwnerID: UUID?

    public init(owners: [Owner] = [], defaultOwnerID: UUID? = nil) {
        entries = owners.map { owner in
            Entry(
                id: owner.id,
                names: owner.allNames.compactMap { OwnerName($0, isCompany: owner.isCompany) },
                addresses: owner.addresses.map(Self.words).filter { $0.count >= 2 }
            )
        }
        self.defaultOwnerID = defaultOwnerID
    }

    /// A name, then an address only one owner has. Several owners named on the page tell nothing, unless all but the default one,
    /// as a company's mail also showing the name of the person who runs it; a line naming several owners, as "Famille Rouvière", tells none.
    public func match(_ lines: [TextLine]) -> Match {
        let top = lines.indices.filter { lines[$0].frame.minY < 0.5 }.sorted { (lines[$0].frame.minY, lines[$0].frame.minX) < (lines[$1].frame.minY, lines[$1].frame.minX) }
        let words = Dictionary(uniqueKeysWithValues: top.map { ($0, Self.words(lines[$0].text)) })
        var ownerLines = Set<Int>()
        var named: [UUID] = []
        for index in top {
            let owners = entries.filter { entry in entry.names.contains { $0.matches(words[index] ?? []) } }
            if !owners.isEmpty { ownerLines.insert(index) }
            if owners.count == 1, !named.contains(owners[0].id) { named.append(owners[0].id) }
        }
        var addressed: [UUID] = []
        for entry in entries {
            var hasAddress = false
            for address in entry.addresses {
                for start in top {
                    guard let block = Self.block(of: address, from: start, among: top, lines: lines, words: words) else { continue }
                    hasAddress = true
                    ownerLines.formUnion(block)
                }
            }
            if hasAddress { addressed.append(entry.id) }
        }
        return Match(owner: decide(named: named, addressed: addressed), ownerLines: ownerLines)
    }

    private func decide(named: [UUID], addressed: [UUID]) -> RecognizedOwner? {
        if named.count == 1 { return RecognizedOwner(id: named[0], clue: .name) }
        let others = named.filter { $0 != defaultOwnerID }
        if named.count > 1 && others.count == 1 { return RecognizedOwner(id: others[0], clue: .name) }
        if addressed.count == 1 { return RecognizedOwner(id: addressed[0], clue: .address) }
        return nil
    }

    /// The lines holding the words of the address, starting at `start` and going down the lines stacked under it, three lines at most.
    private static func block(of address: [String], from start: Int, among top: [Int], lines: [TextLine], words: [Int: [String]]) -> [Int]? {
        var block = [start]
        while true {
            let found = block.flatMap { words[$0] ?? [] }
            if contains(found, address) {
                return block.filter { index in words[index]?.contains(where: address.contains) == true }
            }
            guard block.count < 3, let last = block.last, let next = top.first(where: { isStacked(lines[$0].frame, under: lines[last].frame) }) else { return nil }
            block.append(next)
        }
    }

    /// Right under the line above, starting where it starts or centered on it, as the lines of an address.
    private static func isStacked(_ frame: CGRect, under above: CGRect) -> Bool {
        let gap = frame.minY - above.maxY
        let height = max(frame.height, above.height)
        return frame.minY > above.midY && gap < height * 2 && (abs(frame.minX - above.minX) < 0.05 || abs(frame.midX - above.midX) < 0.03)
    }

    /// Whether every word of `part` is in `whole`, as many times.
    static func contains(_ whole: [String], _ part: [String]) -> Bool {
        var counts = Dictionary(whole.map { ($0, 1) }, uniquingKeysWith: +)
        for word in part {
            guard let count = counts[word], count > 0 else { return false }
            counts[word] = count - 1
        }
        return true
    }

    /// Folded words, split on anything that is not a letter or a digit; a dot between two letters is dropped, so "S.A.S." is "sas" and "Sig.ra" is "sigra".
    static func words(_ text: String) -> [String] {
        var joined = ""
        var previous: Character?
        for (index, character) in zip(text.indices, text) {
            let next = text.index(after: index) < text.endIndex ? text[text.index(after: index)] : nil
            if character == ".", previous?.isLetter == true, next?.isLetter == true { continue }
            joined.append(character)
            previous = character
        }
        return joined.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    static func multiset(_ words: [String]) -> [String: Int] {
        Dictionary(words.map { ($0, 1) }, uniquingKeysWith: +)
    }

    static let civilities: Set<String> = [
        "m", "mr", "mrs", "ms", "miss", "mx", "mme", "mmes", "mlle", "mm", "monsieur", "madame", "mademoiselle", "messieurs", "mesdames",
        "herr", "herrn", "frau", "sr", "sra", "srta", "sres", "don", "dona", "dna", "sig", "sigra", "sigg", "signa", "signor", "signora", "signorina",
        "gentile", "gentmo", "gentma", "egr", "egregio", "spett", "spettle", "dr",
        "famille", "family", "familie", "familia", "famiglia",
    ]
    static let connectors: Set<String> = ["et", "and", "und", "y", "e", "the"]
    static let legalForms: Set<String> = [
        "sas", "sasu", "sarl", "sa", "eurl", "sci", "snc", "scp", "scs", "sca", "selarl", "gie", "eirl",
        "gmbh", "ag", "kg", "ug", "ohg", "gbr", "ev", "kgaa",
        "ltd", "limited", "llc", "llp", "inc", "plc", "corp",
        "sl", "slu", "sll", "srl", "srls", "spa", "sapa", "sprl", "bv", "nv", "bvba",
    ]
    static let genericWords: Set<String> = ["holding", "holdings", "group", "groupe", "gruppe", "grupo", "gruppo", "company", "compagnie", "cie", "co"]
}

/// One name of an owner, with the ways it is printed on mail.
struct OwnerName: Sendable {
    private enum Kind: Sendable {
        /// "Camille Rouvière": in full or with initials, with or without civility; or a civility with a family name.
        case person(words: [String], families: [[String]])
        /// "Famille Rouvière": a civility with the family name.
        case household(family: String)
        /// "Fernwood Holding": with or without its legal form, or without its generic words.
        case company(cores: [[String: Int]])
    }

    private let kind: Kind

    init?(_ name: String, isCompany: Bool) {
        let words = OwnerMatcher.words(name)
        if isCompany || words.contains(where: OwnerMatcher.legalForms.contains) {
            let core = words.filter { !OwnerMatcher.legalForms.contains($0) }
            guard !core.isEmpty else { return nil }
            let short = core.filter { !OwnerMatcher.genericWords.contains($0) }
            kind = .company(cores: [core, short].filter { !$0.isEmpty }.map(OwnerMatcher.multiset))
            return
        }
        let plain = words.filter { !Self.isIgnored($0) }
        if plain.count >= 2 {
            let rest = Array(plain.dropFirst())
            kind = .person(words: plain, families: ([[plain[plain.count - 1]], rest] + rest.map { [$0] }).reduce(into: []) { families, family in
                if !families.contains(family) { families.append(family) }
            })
        } else if plain.count == 1, words.contains(where: OwnerMatcher.civilities.contains) {
            kind = .household(family: plain[0])
        } else {
            return nil
        }
    }

    private static func isIgnored(_ word: String) -> Bool {
        OwnerMatcher.civilities.contains(word) || OwnerMatcher.connectors.contains(word)
    }

    func matches(_ line: [String]) -> Bool {
        guard !line.isEmpty else { return false }
        switch kind {
        case let .person(words, families):
            return Self.isFullName(words, line) || families.contains { Self.isCivility(with: $0, line) }
        case let .household(family):
            return Self.isCivility(with: [family], line)
        case let .company(cores):
            let rest = OwnerMatcher.multiset(line.filter { !OwnerMatcher.legalForms.contains($0) })
            return cores.contains(rest)
        }
    }

    /// Every word of the name, some maybe as their initial but one at least in full, and nothing else but civilities.
    private static func isFullName(_ name: [String], _ line: [String]) -> Bool {
        var left = line
        var initials: [String] = []
        for word in name {
            if let index = left.firstIndex(of: word) {
                left.remove(at: index)
            } else {
                initials.append(word)
            }
        }
        guard initials.count < name.count else { return false }
        for word in initials {
            guard let index = left.firstIndex(where: { $0.count == 1 && word.hasPrefix($0) }) else { return false }
            left.remove(at: index)
        }
        return left.allSatisfy(isIgnored)
    }

    /// A civility, such as "Mme" or "Famille", with the family name and nothing else: "M. et Mme Rouvière".
    private static func isCivility(with family: [String], _ line: [String]) -> Bool {
        line.contains(where: OwnerMatcher.civilities.contains) && OwnerMatcher.multiset(line.filter { !isIgnored($0) }) == OwnerMatcher.multiset(family)
    }
}

extension Owner {
    /// Its own name, unless still the placeholder, then its other names.
    public var allNames: [String] {
        (hasPlaceholderName ? [] : [name]) + names
    }

    /// Its names are company names, as are the names with a legal form.
    var isCompany: Bool {
        kind == .company
    }

    /// Whether the two addresses are the same, whatever their case, accents, punctuation and word order.
    public static func isSameAddress(_ address: String, as other: String) -> Bool {
        let words = OwnerMatcher.words(address)
        return !words.isEmpty && OwnerMatcher.multiset(words) == OwnerMatcher.multiset(OwnerMatcher.words(other))
    }
}

extension Owner {
    /// How mail may also print its names, for Settings to show: "C. Rouvière", "Mme Rouvière", "Fernwood SAS"…, with the civilities and legal forms of the user's country.
    public func otherForms(region: String?, language: String?) -> [String] {
        let style = NameStyle(region: region, language: language)
        let typed = allNames.map { OwnerMatcher.multiset(OwnerMatcher.words($0)) }
        var seen = Set(typed)
        var forms: [String] = []
        for (index, name) in allNames.enumerated() {
            for form in Self.forms(of: name, isCompany: isCompany, style: style, isMain: index == 0 && !hasPlaceholderName) {
                if seen.insert(OwnerMatcher.multiset(OwnerMatcher.words(form))).inserted { forms.append(form) }
            }
        }
        return forms
    }

    private static func forms(of name: String, isCompany: Bool, style: NameStyle, isMain: Bool) -> [String] {
        let tokens = name.split(whereSeparator: \.isWhitespace).map(String.init)
        let words = tokens.map(OwnerMatcher.words)
        if isCompany || words.joined().contains(where: OwnerMatcher.legalForms.contains) {
            let isLegalForm = { (words: [String]) in !words.isEmpty && words.allSatisfy(OwnerMatcher.legalForms.contains) }
            let form = zip(tokens, words).first { isLegalForm($1) }?.0 ?? style.legalForm
            let core = zip(tokens, words).filter { !isLegalForm($1) }
            let short = core.filter { !$1.allSatisfy(OwnerMatcher.genericWords.contains) }
            guard !core.isEmpty else { return [] }
            let coreName = core.map(\.0).joined(separator: " ")
            let shortName = short.map(\.0).joined(separator: " ")
            return [coreName + " " + form] + (short.isEmpty ? [] : [shortName + " " + form, shortName]) + [coreName]
        }
        let plain = zip(tokens, words).filter { !$1.isEmpty && !$1.allSatisfy { OwnerMatcher.civilities.contains($0) || OwnerMatcher.connectors.contains($0) } }.map(\.0)
        guard let family = plain.last else { return [] }
        let civilities = style.civilities(family)
        if plain.count == 1 {
            return words.joined().contains(where: OwnerMatcher.civilities.contains) ? civilities : []
        }
        let initial = plain[0].first.map { "\($0.uppercased())." } ?? ""
        let initialed = ([initial] + plain.dropFirst()).joined(separator: " ")
        return [initialed] + (isMain ? civilities : Array(civilities.prefix(1)))
    }
}

/// The civilities and legal form mail uses in a country.
private enum NameStyle {
    case french, german, spanish, italian, english, american

    init(region: String?, language: String?) {
        switch region {
        case "FR", "BE", "LU", "MC": self = .french
        case "DE", "AT", "LI": self = .german
        case "ES": self = .spanish
        case "IT", "SM": self = .italian
        case "US": self = .american
        default:
            switch language {
            case "fr": self = .french
            case "de": self = .german
            case "es": self = .spanish
            case "it": self = .italian
            default: self = .english
            }
        }
    }

    var legalForm: String {
        switch self {
        case .french: "SAS"
        case .german: "GmbH"
        case .spanish: "SL"
        case .italian: "SRL"
        case .english: "Ltd"
        case .american: "LLC"
        }
    }

    func civilities(_ family: String) -> [String] {
        switch self {
        case .french: ["Mme \(family)", "M. et Mme \(family)", "Famille \(family)"]
        case .german: ["Frau \(family)", "Herrn und Frau \(family)", "Familie \(family)"]
        case .spanish: ["Sra. \(family)", "Sr. y Sra. \(family)", "Familia \(family)"]
        case .italian: ["Sig.ra \(family)", "Sig. e Sig.ra \(family)", "Famiglia \(family)"]
        case .english, .american: ["Mrs \(family)", "Mr and Mrs \(family)", "The \(family) Family"]
        }
    }
}
