import CoreGraphics
import Foundation
import ScannerKit
import Testing

struct FileNamerTests {
    let namer = FileNamer(monthFirst: false)
    let today = Date(timeIntervalSince1970: 1_794_700_000)

    @Test func replacesForbiddenCharactersByADash() {
        #expect(namer.sanitize("Invoice 12/2026: \"final\"?") == "Invoice 12-2026- -final--")
        #expect(namer.sanitize("..hidden") == "hidden")
        #expect(namer.sanitize("line\nbreak") == "line-break")
    }

    @Test func finalNameIsTrimmedAndNeverEmpty() {
        #expect(namer.finalName("  Lumen   invoice ", fallback: "Scan") == "Lumen invoice")
        #expect(namer.finalName("   ", fallback: "Scan") == "Scan")
    }

    @Test func limitsTheLength() {
        #expect(namer.sanitize(String(repeating: "a", count: 200)).count == 80)
    }

    @Test func suggestsTypeIssuerAndNumber() {
        let lines = [
            line("Facture n° 2026FA0004711", y: 0.03, height: 0.012),
            line("OFFICE DU TOURISME DES", y: 0.12, height: 0.016),
            line("3, QUAI DES TILLEULS", y: 0.15, height: 0.008),
            line("Jeanne MARTIN", y: 0.2, height: 0.013),
            line("Lyon, le 6 octobre 2026,", y: 0.3, height: 0.013),
        ]
        let suggestions = namer.suggestions(lines: lines, date: today)
        #expect(suggestions.names == ["Facture Office du Tourisme des", "Facture 2026FA0004711"])
        #expect(suggestions.date.map(FileNamer.isoDate) == "2026-10-06")
    }

    @Test func usesAHeadingAsTheType() {
        let lines = [line("RECEPISSE DE DECLARATION DE TRAVAUX", y: 0.2, height: 0.015), line("Adresse : 12 R DES LILAS", y: 0.25, height: 0.012)]
        #expect(namer.suggestions(lines: lines, date: today).names.first == "Recepisse de declaration de travaux")
    }

    @Test func ignoresUncertainTextRecipientsAndLabels() {
        let lines = [
            TextLine(text: "ORIZON MOBILIT", frame: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.03), confidence: 0.3),
            TextLine(text: "Jeanne MARTIN", frame: CGRect(x: 0.6, y: 0.15, width: 0.3, height: 0.02)),
            line("Forme juridique : Société", y: 0.2, height: 0.02),
            line("Invoice 1234", y: 0.25, height: 0.01),
        ]
        #expect(namer.suggestions(lines: lines, date: today).names.first == "Invoice 1234")
    }

    @Test func usesTheIssuerAloneWithoutAType() {
        let lines = [line("Lumen Energy", y: 0.05, height: 0.03), line("12 rue des Lilas, 75011 Paris", y: 0.09, height: 0.01)]
        #expect(namer.suggestions(lines: lines, date: today).names.first == "Lumen Energy")
    }

    @Test func fallsBackToTheDateWithoutText() {
        #expect(namer.suggestions(lines: [], date: today) == NameSuggestions(names: ["Scan \(isoToday)"], date: nil))
    }

    @Test(arguments: [
        ("Date: 2026-03-04", "2026-03-04"),
        ("Le 04/03/2026", "2026-03-04"),
        ("25.12.2026", "2026-12-25"),
        ("1er janvier 2027", "2027-01-01"),
        ("March 4, 2026", "2026-03-04"),
        ("12 Nov. 2026", "2026-11-12"),
    ])
    func readsDates(text: String, expected: String) {
        let date = namer.suggestions(lines: [line("Invoice 1234", y: 0.1, height: 0.02), line(text, y: 0.2, height: 0.01)], date: today).date
        #expect(date.map(FileNamer.isoDate) == expected)
    }

    @Test func readsAmbiguousDatesMonthFirstWhenAsked() {
        let lines = [line("Invoice 1234", y: 0.1, height: 0.02), line("03/04/2026", y: 0.2, height: 0.01)]
        #expect(FileNamer(monthFirst: true).suggestions(lines: lines, date: today).date.map(FileNamer.isoDate) == "2026-03-04")
    }

    private var isoToday: String { today.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()) }

    private func line(_ text: String, y: CGFloat, height: CGFloat) -> TextLine {
        TextLine(text: text, frame: CGRect(x: 0.1, y: y, width: 0.5, height: height))
    }
}

struct FileNameFormatTests {
    let date = ISO8601DateFormatter().date(from: "2026-11-12T12:00:00Z")!

    @Test func keepsTheNameByDefault() {
        #expect(FileNameFormat().fileName(name: "Lumen Energy invoice", date: date) == "Lumen Energy invoice")
    }

    @Test func datesDashesAndLowercase() {
        let format = FileNameFormat(datePrefix: true, separator: .dash, lowercase: true)
        #expect(format.fileName(name: "Lumen Energy invoice", date: date) == "2026-11-12-lumen-energy-invoice")
        #expect(format.fileName(name: "Attestation d'assurance habitation", date: date) == "2026-11-12-attestation-d-assurance-habitation")
        #expect(format.fileName(name: "Facture n° 2026FA0004711", date: date) == "2026-11-12-facture-n-2026fa0004711")
    }

    @Test func underscoresKeepTheDateWithDashes() {
        let format = FileNameFormat(datePrefix: true, separator: .underscore)
        #expect(format.fileName(name: "Lumen Energy invoice", date: date) == "2026-11-12_Lumen_Energy_invoice")
    }

    @Test func keepsAccents() {
        #expect(FileNameFormat(separator: .dash, lowercase: true).fileName(name: "Bénéficiaires effectifs", date: date) == "bénéficiaires-effectifs")
    }

    @Test func neverRepeatsTheDate() {
        let format = FileNameFormat(datePrefix: true, separator: .dash, lowercase: true)
        #expect(format.fileName(name: "Scan 2026-11-12", date: date) == "2026-11-12-scan")
        #expect(format.fileName(name: "2026-11-12 Lumen invoice", date: date) == "2026-11-12-lumen-invoice")
        #expect(FileNameFormat(separator: .dash).fileName(name: "2026-11-12 Lumen", date: date) == "2026-11-12-Lumen")
    }

    @Test func fallsBackToTheDate() {
        #expect(FileNameFormat(separator: .dash).fileName(name: " ?! ", date: date) == "2026-11-12")
    }
}
