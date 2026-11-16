import Foundation
import ScannerKit
import ScannerKitTesting
import Testing

struct FileNameFormatTests {
    let date = Date.day("2026-11-12")
    let scanDate = Date.day("2026-11-16")

    private func name(_ format: FileNameFormat, _ name: String) -> String {
        format.fileName(name: name, details: DocumentDetails(date: date), scanDate: scanDate)
    }

    @Test func keepsTheNameByDefault() {
        #expect(name(FileNameFormat(), "Lumen Energy invoice") == "Lumen Energy invoice")
    }

    @Test func datesDashesAndLowercase() {
        let format = FileNameFormat(datePosition: .start, separator: .dash, lowercase: true)
        #expect(name(format, "Lumen Energy invoice") == "2026-11-12-lumen-energy-invoice")
        #expect(name(format, "Attestation d'assurance habitation") == "2026-11-12-attestation-d-assurance-habitation")
        #expect(name(format, "Facture n° 2026FA0004711") == "2026-11-12-facture-n-2026fa0004711")
    }

    @Test func underscoresKeepTheDateWithDashes() {
        #expect(name(FileNameFormat(datePosition: .start, separator: .underscore), "Lumen Energy invoice") == "2026-11-12_Lumen_Energy_invoice")
    }

    @Test func putsTheDateAtTheEnd() {
        #expect(name(FileNameFormat(datePosition: .end, separator: .dash), "Lumen Energy invoice") == "Lumen-Energy-invoice-2026-11-12")
    }

    @Test(arguments: [(FileNameFormat.DateStyle.day, "2026-11-12 Lumen"), (.compactDay, "20261112 Lumen"), (.month, "2026-11 Lumen")])
    func formatsTheDate(style: FileNameFormat.DateStyle, expected: String) {
        #expect(name(FileNameFormat(datePosition: .start, dateStyle: style), "Lumen") == expected)
    }

    @Test func usesTheScanDayWhenAsked() {
        #expect(name(FileNameFormat(datePosition: .start, dateSource: .scan), "Lumen") == "2026-11-16 Lumen")
        #expect(FileNameFormat(datePosition: .start).fileName(name: "Lumen", scanDate: scanDate) == "2026-11-16 Lumen")
    }

    @Test func dropsAccents() {
        #expect(name(FileNameFormat(separator: .dash, lowercase: true), "Facture d’électricité") == "facture-d-electricite")
        #expect(name(FileNameFormat(), "Œuvre Straße Москва") == "OEuvre Strasse Москва")
    }

    @Test func dropsAccentsInACustomFormat() {
        let format = FileNameFormat(isCustom: true, template: "Santé/{CATEGORY} {ISSUER} {NAME}")
        let details = DocumentDetails(category: DocumentCategory(rawValue: "Reçu"), issuer: "Société Générale", date: date)
        #expect(format.fileName(name: "Prêt", details: details, scanDate: scanDate) == "Sante/Recu Societe Generale Pret")
    }

    @Test func neverRepeatsTheDate() {
        let format = FileNameFormat(datePosition: .start, separator: .dash, lowercase: true)
        #expect(name(format, "Scan 2026-11-12") == "2026-11-12-scan")
        #expect(name(format, "2026-11-12 Lumen invoice") == "2026-11-12-lumen-invoice")
        #expect(name(FileNameFormat(datePosition: .start, dateStyle: .compactDay), "Lumen 2026-11-12") == "20261112 Lumen")
        #expect(name(FileNameFormat(separator: .dash), "2026-11-12 Lumen") == "2026-11-12-Lumen")
        #expect(name(FileNameFormat(separator: .underscore), "Lumen 2026-11-12") == "Lumen_2026-11-12")
    }

    @Test func fallsBackToTheDate() {
        #expect(name(FileNameFormat(separator: .dash), " ?! ") == "2026-11-12")
    }

    // MARK: Custom format

    let lumen = DocumentDetails(category: .invoice, issuer: "Lumen Energy", date: .day("2026-11-12"), number: "2026-0042")

    private func custom(_ template: String, separator: FileNameFormat.Separator = .space, lowercase: Bool = false, dateSource: FileNameFormat.DateSource = .document) -> FileNameFormat {
        FileNameFormat(dateSource: dateSource, separator: separator, lowercase: lowercase, isCustom: true, template: template)
    }

    @Test func fillsTheVariablesOfACustomFormat() {
        let details = DocumentDetails(date: date)
        #expect(custom("{YYYY}-{MM} archive {NAME}").fileName(name: "Lumen Energy invoice", details: details, scanDate: scanDate) == "2026-11 archive Lumen Energy invoice")
        #expect(custom("{YYYY}-{MM} archive {NAME}", separator: .dash, lowercase: true).fileName(name: "Lumen Energy invoice", details: details, scanDate: scanDate) == "2026-11-archive-lumen-energy-invoice")
        #expect(custom("{YY}{MM}{DD} {CATEGORY} {ISSUER} {NUMBER}").fileName(name: "x", details: lumen, scanDate: scanDate) == "261112 Invoice Lumen Energy 2026-0042")
        #expect(custom("{YYYY}-{MM}-{DD} {NAME}", dateSource: .scan).fileName(name: "Lumen", details: lumen, scanDate: scanDate) == "2026-11-16 Lumen")
    }

    @Test func putsScansInFolders() {
        #expect(custom("{CATEGORY}/{YYYY} {ISSUER}").fileName(name: "x", details: lumen, scanDate: scanDate) == "Invoice/2026 Lumen Energy")
        #expect(custom("{CATEGORY}/{YYYY}/{MM} {NAME}").fileName(name: "Bill", details: lumen, scanDate: scanDate) == "Invoice/2026/11 Bill")
        #expect(custom("Paperwork/{CATEGORY}/{NAME}", separator: .underscore, lowercase: true).fileName(name: "Lumen bill", details: DocumentDetails(category: .bankStatement), scanDate: scanDate) == "Paperwork/bank_statement/lumen_bill")
    }

    @Test func dropsEmptyValuesWithTheirSeparator() {
        let noIssuer = DocumentDetails(category: .invoice, date: date)
        #expect(custom("{CATEGORY}/{YYYY} {ISSUER}").fileName(name: "x", details: noIssuer, scanDate: scanDate) == "Invoice/2026")
        #expect(custom("{ISSUER} - {NAME}").fileName(name: "Bill", details: noIssuer, scanDate: scanDate) == "Bill")
        #expect(custom("{YYYY}-{MM} {ISSUER} {NUMBER} {NAME}").fileName(name: "Bill", details: noIssuer, scanDate: scanDate) == "2026-11 Bill")
        #expect(custom("{ISSUER}/{NAME}").fileName(name: "Bill", details: noIssuer, scanDate: scanDate) == "Bill")
        #expect(custom("{ISSUER}").fileName(name: "Bill", details: noIssuer, scanDate: scanDate) == "2026-11-12")
    }

    @Test func aSlashInAValueNeverMakesAFolder() {
        let details = DocumentDetails(issuer: "A/B Services", number: "../12")
        #expect(custom("{ISSUER} {NUMBER}").fileName(name: "x", details: details, scanDate: scanDate) == "A-B Services -12")
        #expect(custom("{ISSUER}/{NAME}").fileName(name: "..", details: DocumentDetails(issuer: ".."), scanDate: scanDate) == "2026-11-16")
    }

    @Test func aSuggestedNameLeavesOutWhatTheFormatShows() {
        let parts = SuggestedParts(type: "Facture", issuer: "Lumen Energy", number: "2026-0042")
        let format = custom("{CATEGORY} {ISSUER} {NAME}")
        #expect(format.fileName(name: "Facture Lumen Energy", details: lumen, scanDate: scanDate, suggestedParts: parts) == "Invoice Lumen Energy")
        #expect(custom("{ISSUER} {NAME}").fileName(name: "Facture Lumen Energy", details: lumen, scanDate: scanDate, suggestedParts: parts) == "Lumen Energy Facture")
        #expect(custom("{CATEGORY} {NUMBER} {NAME}").fileName(name: "Facture 2026-0042", details: lumen, scanDate: scanDate, suggestedParts: parts) == "Invoice 2026-0042")
        #expect(custom("{YYYY}-{MM}-{DD} {NAME}").fileName(name: "Scan 2026-11-16", details: lumen, scanDate: scanDate, suggestedParts: SuggestedParts()) == "2026-11-12 Scan")
        #expect(format.fileName(name: "Facture Lumen Energy", details: lumen, scanDate: scanDate) == "Invoice Lumen Energy Facture Lumen Energy")
    }

    @Test func theSimpleFormatIgnoresSuggestedParts() {
        let parts = SuggestedParts(type: "Facture", issuer: "Lumen Energy")
        let format = FileNameFormat(datePosition: .start, separator: .dash, template: "{ISSUER}")
        #expect(format.fileName(name: "Facture Lumen Energy", details: lumen, scanDate: scanDate, suggestedParts: parts) == "2026-11-12-Facture-Lumen-Energy")
    }

    @Test(arguments: [
        ("", FileNameFormat.Template.ParseError.empty),
        ("{NAME} {FOO}", .unknownVariable("FOO")),
        ("{name}", .unknownVariable("name")),
        ("{NAME", .unclosedBrace),
        ("{NAME}: {YYYY}", .forbiddenCharacter(":")),
        ("/{NAME}", .emptyFolder),
        ("{CATEGORY}//{NAME}", .emptyFolder),
        ("{NAME}/", .emptyFolder),
        ("../{NAME}", .relativeFolder),
        ("{CATEGORY}/ . /{NAME}", .relativeFolder),
    ])
    func rejectsInvalidTemplates(template: String, error: FileNameFormat.Template.ParseError) {
        #expect(throws: error) { try FileNameFormat.Template(template) }
    }

    @Test func ignoresAnExtensionTypedInTheFormat() throws {
        #expect(custom("{NAME}.pdf").fileName(name: "Bill", scanDate: scanDate) == "Bill")
    }

    @Test func anInvalidCustomFormatGivesTheSimpleFormat() {
        #expect(custom("{FOO} {NAME}").fileName(name: "Lumen Energy invoice", details: lumen, scanDate: scanDate) == "Lumen Energy invoice")
    }

    // MARK: Segments

    @Test func tellsWhereEachPartOfASimpleFileNameComesFrom() {
        let format = FileNameFormat(datePosition: .start, separator: .dash, lowercase: true)
        #expect(format.segments(name: "Lumen Energy invoice", details: DocumentDetails(date: date), scanDate: scanDate) == [
            FileNameSegment("2026-11-12", .date), FileNameSegment("-", .text), FileNameSegment("lumen-energy-invoice", .name),
        ])
        #expect(FileNameFormat().segments(name: " ", scanDate: scanDate) == [FileNameSegment("2026-11-16", .date)])
    }

    @Test func tellsWhereEachPartOfACustomFileNameComesFrom() {
        let format = custom("{CATEGORY}/{YYYY}-{MM} {ISSUER} {NAME}")
        #expect(format.segments(name: "October", details: lumen, scanDate: scanDate) == [
            FileNameSegment("Invoice", .category), FileNameSegment("/", .folderSeparator),
            FileNameSegment("2026", .date), FileNameSegment("-", .text), FileNameSegment("11", .date), FileNameSegment(" ", .text),
            FileNameSegment("Lumen Energy", .issuer), FileNameSegment(" ", .text), FileNameSegment("October", .name),
        ])
    }

    @Test func keepsAnEmptyNameSegmentWhereTheNameWouldGo() {
        let format = custom("{CATEGORY} {ISSUER} {NAME}")
        let parts = SuggestedParts(type: "Facture", issuer: "Lumen Energy")
        let segments = format.segments(name: "Facture Lumen Energy", details: lumen, scanDate: scanDate, suggestedParts: parts)
        #expect(segments == [FileNameSegment("Invoice", .category), FileNameSegment(" ", .text), FileNameSegment("Lumen Energy", .issuer), FileNameSegment("", .name)])
        #expect(segments.map(\.text).joined() == "Invoice Lumen Energy")
    }
}
