import CoreGraphics
import Foundation
import ScannerKit
import ScannerKitTesting
import Testing

struct DocumentDetectorTests {
    @Test func reportsHitRatesOnTheCorpus() {
        let report = CorpusReport(documents: DocumentCorpus.documents)
        let learned = CorpusReport(documents: DocumentCorpus.documents, ownLines: DocumentCorpus.ownLines)
        print("First scans:\n\(report.table)\n\(report.misses.joined(separator: "\n"))")
        print("With the user's own lines learned:\n\(learned.table)")
    }
}

/// Hit rates per detail and language over made-up documents.
struct CorpusReport {
    struct Tally {
        var hits = 0
        var total = 0
        var rate: String { total == 0 ? "-" : "\(hits)/\(total)" }
    }

    static let details = ["category", "issuer", "date", "number"]
    var tallies: [String: [String: Tally]] = [:]
    var misses: [String] = []

    init(documents: [CorpusDocument], ownLines: Set<String> = []) {
        for document in documents {
            let detected = DocumentDetector(monthFirst: document.monthFirst).detect(lines: document.lines, ownLines: ownLines)
            let found = detected.details
            let checks: [(String, Bool, String)] = [
                ("category", found.category == document.category, found.category.rawValue),
                ("issuer", Self.sameIssuer(found.issuer, document.issuer), found.issuer ?? "nil"),
                ("date", found.date.map(Self.iso) == document.date, found.date.map(Self.iso) ?? "nil"),
                ("number", found.number == document.number, found.number ?? "nil"),
            ]
            for (detail, hit, value) in checks {
                for language in [document.language.prefix(2).description, "all"] {
                    tallies[detail, default: [:]][language, default: Tally()].total += 1
                    if hit { tallies[detail, default: [:]][language, default: Tally()].hits += 1 }
                }
                if !hit { misses.append("\(document.name) \(detail): got \(value)") }
            }
        }
    }

    func rate(_ detail: String, _ language: String = "all") -> Double {
        let tally = tallies[detail]?[language] ?? Tally()
        return tally.total == 0 ? 0 : Double(tally.hits) / Double(tally.total)
    }

    var table: String {
        let languages = ["en", "fr", "de", "es", "it", "all"]
        let header = "detail    " + languages.map { $0.padding(toLength: 7, withPad: " ", startingAt: 0) }.joined()
        let rows = Self.details.map { detail in
            detail.padding(toLength: 10, withPad: " ", startingAt: 0) + languages.map { (tallies[detail]?[$0]?.rate ?? "-").padding(toLength: 7, withPad: " ", startingAt: 0) }.joined()
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func sameIssuer(_ found: String?, _ expected: String?) -> Bool {
        found.map(normalized) == expected.map(normalized)
    }

    private static let legalForms: Set<String> = ["sa", "sas", "sarl", "gmbh", "ag", "eg", "ltd", "plc", "inc", "llc", "sl", "spa", "srl", "bv"]

    private static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacing(".", with: "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "&" })
            .filter { !legalForms.contains(String($0)) }
            .joined(separator: " ")
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
    }
}
