import Foundation
import NaturalLanguage

/// What tells issuers apart on a page: web and email domains, company identifiers, names followed by a legal form.
struct IssuerEvidence {
    struct Domain {
        var domain: String
        var isInHeaderOrFooter: Bool
    }

    struct LegalName {
        var name: String
        var line: String
        var isInHeaderOrFooter: Bool
        var hasIdentifier: Bool
    }

    var domains: [Domain] = []
    /// Without spaces, such as FR12123456789 or 123456789 for a SIREN.
    var identifiers: [String] = []
    var legalNames: [LegalName] = []

    init(page: DocumentDetector.Page) {
        for line in page.lines where !line.isOwn {
            let isInHeaderOrFooter = line.frame.minY < 0.3 || line.frame.minY > 0.8
            for domain in Self.domains(in: line.text) where !domains.contains(where: { $0.domain == domain }) {
                domains.append(Domain(domain: domain, isInHeaderOrFooter: isInHeaderOrFooter))
            }
            let lineIdentifiers = Self.identifiers(in: line.text)
            for identifier in lineIdentifiers where !identifiers.contains(identifier) {
                identifiers.append(identifier)
            }
            for name in Self.legalNames(in: line) {
                legalNames.append(LegalName(name: name, line: line.text, isInHeaderOrFooter: isInHeaderOrFooter, hasIdentifier: !lineIdentifiers.isEmpty))
            }
        }
    }

    /// Domains that match the issuer first, then the other domains of the header and footer, then identifiers.
    func keys(for issuer: String?) -> [String] {
        let matching = domains.filter { DocumentDetector.domain($0.domain, matches: issuer ?? "") }
        let others = domains.filter { $0.isInHeaderOrFooter && !DocumentDetector.domain($0.domain, matches: issuer ?? "") }
        return (matching + others).map(\.domain) + identifiers
    }

    // MARK: Domains

    private static let topLevelDomains: Set<String> = ["fr", "com", "de", "es", "it", "uk", "org", "net", "eu", "be", "ch", "at", "lu", "io", "info", "biz", "us", "ca", "ie", "nl", "pt", "me"]
    private static let secondLevelDomains: Set<String> = ["co", "org", "gov", "ac", "gouv", "com", "gob", "net"]

    /// Registrable domains of the web and email addresses on a line, without www. and without mail providers.
    static func domains(in text: String) -> [String] {
        guard text.contains(".") || text.contains("@") else { return [] }
        return text.lowercased().split(whereSeparator: { $0.isWhitespace || "·|,;()<>".contains($0) }).compactMap { word in
            guard word.contains("."), word.contains(where: \.isLetter) else { return nil }
            var host = word.trimmingCharacters(in: CharacterSet(charactersIn: ".:;"))
            if let at = host.lastIndex(of: "@") {
                host = String(host[host.index(after: at)...])
            } else if let scheme = host.range(of: "://") {
                host = String(host[scheme.upperBound...].prefix { $0 != "/" })
            } else if !host.hasPrefix("www.") && !host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }) {
                return nil
            }
            let labels = host.split(separator: ".").map(String.init).filter { $0 != "www" }
            guard labels.count >= 2, let tld = labels.last, topLevelDomains.contains(tld), labels.allSatisfy({ $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) else { return nil }
            let keep = labels.count >= 3 && secondLevelDomains.contains(labels[labels.count - 2]) ? 3 : 2
            let registrable = labels.suffix(keep)
            guard let stem = registrable.first, stem.count >= 3, stem.contains(where: \.isLetter), !DocumentVocabulary.mailProviders.contains(stem) else { return nil }
            return registrable.joined(separator: ".")
        }
    }

    // MARK: Identifiers

    private static let identifierPatterns: [(NSRegularExpression, @Sendable ([String]) -> [String])] = {
        let patterns: [(String, @Sendable ([String]) -> [String])] = [
            (#"SIRET\s*(?:N°|Nº)?\s*:?\s*((?:\d\s?){14})"#, { [String($0[0].filter(\.isNumber).prefix(9))] }),
            (#"(?:SIREN|RCS)\s*(?:N°|Nº)?\s*:?\s*(?:[A-ZÀ-Ü\-]+\s+)?((?:\d\s?){8}\d)(?!\s?\d)"#, { [$0[0]] }),
            (#"(?<!IBAN )(?<![A-Z0-9])FR\s?(\d{2})\s?((?:\d\s?){8}\d)(?!\s?\d)"#, { ["FR\($0[0])\($0[1])", $0[1]] }),
            (#"(?<![A-Z0-9])DE\s?(\d{9})(?!\d)"#, { ["DE\($0[0])"] }),
            (#"VAT[^\d]{0,16}GB\s?((?:\d\s?){8}\d)(?!\s?\d)"#, { ["GB\($0[0])"] }),
            (#"(?:P\.\s?IVA|PARTITA IVA)[^\d]{0,12}(\d{11})(?!\d)"#, { ["IT\($0[0])"] }),
            (#"(?:CIF|NIF)\s*:?\s*([A-HJNP-SUVW]-?\d{7}[0-9A-J])(?![0-9A-Z])"#, { ["ES\($0[0])"] }),
            (#"(?:COMPANY|REGISTERED IN [A-Z ]+?)\s+(?:NO|NUMBER)\.?\s*:?\s*(\d{8})(?!\d)"#, { ["CRN\($0[0])"] }),
            (#"\b(HR[AB]\s?\d{3,6})(?!\d)"#, { [$0[0]] }),
            (#"RPPS\s*:?\s*(\d{11})(?!\d)"#, { ["RPPS\($0[0])"] }),
        ]
        return patterns.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
    }()

    /// Company identifiers written next to their label: SIRET and SIREN, VAT numbers, registration numbers.
    static func identifiers(in text: String) -> [String] {
        guard text.count(where: \.isNumber) >= 3 else { return [] }
        let text = text.uppercased()
        var found: [String] = []
        for (pattern, identifiers) in identifierPatterns {
            for groups in pattern.groups(in: text) {
                for identifier in identifiers(groups).map({ $0.filter { !$0.isWhitespace && $0 != "-" } }) where !found.contains(identifier) {
                    found.append(identifier)
                }
            }
        }
        return found
    }

    // MARK: Names

    private static let connectors: Set<String> = ["&", "de", "du", "des", "di", "del", "della", "delle", "y", "et", "und", "and", "of", "le", "la", "les", "il"]
    private static let sentenceStarts: Set<String> = ["tra", "entre", "between", "zwischen", "der", "die", "das", "the", "el", "par", "by", "from", "con", "with", "mit"]

    /// The capitalized words right before a legal form: "Voltaria Énergie" in "Voltaria Énergie SAS au capital de 500 000 €".
    static func legalNames(in line: DocumentDetector.Line) -> [String] {
        let tokens = line.tokens
        var names: [String] = []
        for (index, token) in tokens.enumerated() where index > 0 && DocumentDetector.isLegalForm(token) {
            var words: [Substring] = []
            for previous in tokens[..<index].reversed() {
                var text = previous.text
                if words.isEmpty, text.hasSuffix(",") { text = text.dropLast() }
                guard !text.isEmpty, !text.hasSuffix(","), !text.hasSuffix(":"), !text.hasSuffix(")"), !"·|-–—(".contains(text) else { break }
                let isConnector = connectors.contains(previous.key)
                guard isConnector || text.first?.isUppercase == true, words.count < 6 else { break }
                words.insert(text, at: 0)
            }
            while let first = words.first, connectors.contains(DocumentDetector.folded(first)) || sentenceStarts.contains(DocumentDetector.folded(first)) {
                words.removeFirst()
            }
            guard words.contains(where: { $0.filter(\.isLetter).count >= 2 }) else { continue }
            names.append(DocumentDetector.titleCased(words.map(String.init)))
        }
        return names
    }
}

extension DocumentDetector {
    /// Folded letters of the organizations NaturalLanguage names on the page.
    static func organizations(in page: Page) -> [String] {
        let text = page.lines.filter { !$0.isOwn }.map(\.text).joined(separator: "\n")
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            let name = letters(String(text[range]))
            if tag == .organizationName, name.count >= 4, !found.contains(name) { found.append(name) }
            return true
        }
        return found
    }
}

extension NSRegularExpression {
    /// The captured groups of every match, empty when a group did not take part.
    func groups(in text: String) -> [[String]] {
        matches(in: text, range: NSRange(text.startIndex..., in: text)).map { result in
            (1..<result.numberOfRanges).map { Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }
}
