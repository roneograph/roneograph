import Foundation
import ScannerKit
import Testing

struct FileNamerTests {
    let today = Date(timeIntervalSince1970: 1_794_700_000)

    @Test func replacesForbiddenCharactersByADash() {
        #expect(FileNamer.sanitize("Invoice 12/2026: \"final\"?") == "Invoice 12-2026- -final--")
        #expect(FileNamer.sanitize("..hidden") == "hidden")
        #expect(FileNamer.sanitize("line\nbreak") == "line-break")
    }

    @Test func finalNameIsTrimmedAndNeverEmpty() {
        #expect(FileNamer.finalName("  Lumen   invoice ", fallback: "Scan") == "Lumen invoice")
        #expect(FileNamer.finalName("   ", fallback: "Scan") == "Scan")
    }

    @Test func limitsTheLength() {
        #expect(FileNamer.sanitize(String(repeating: "a", count: 200)).count == 80)
    }

    @Test func numbersANameThatIsTaken() {
        let taken: Set = ["Invoice", "Invoice-2"]
        #expect(FileNamer.available("Invoice", separator: "-") { taken.contains($0) } == "Invoice-3")
        #expect(FileNamer.available("Quote", separator: "-") { taken.contains($0) } == "Quote")
    }

    @Test func suggestsTheTypeWithTheIssuerThenWithTheNumber() {
        let parts = SuggestedParts(type: "Facture", issuer: "Office du Tourisme", number: "2026FA0004711")
        #expect(FileNamer.names(for: parts, date: today) == ["Facture Office du Tourisme", "Facture 2026FA0004711"])
    }

    @Test func suggestsTheTypeWithTheNumberWithoutAnIssuer() {
        #expect(FileNamer.names(for: SuggestedParts(type: "Invoice", number: "1234"), date: today) == ["Invoice 1234"])
    }

    @Test func usesTheIssuerAloneWithoutAType() {
        #expect(FileNamer.names(for: SuggestedParts(issuer: "Lumen Energy", number: "1234"), date: today) == ["Lumen Energy"])
    }

    @Test func keepsSuggestionsValid() {
        #expect(FileNamer.names(for: SuggestedParts(type: "Invoice", issuer: "Lumen: Energy"), date: today) == ["Invoice Lumen- Energy"])
    }

    @Test func fallsBackToTheDateWithoutParts() {
        #expect(FileNamer.names(for: SuggestedParts(), date: today) == ["Scan \(isoToday)"])
    }

    private var isoToday: String { today.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()) }
}
