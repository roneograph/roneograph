import Foundation
import ScannerKit
import Testing

struct FileNameFormatTests {
    let date = ISO8601DateFormatter().date(from: "2026-11-12T12:00:00Z")!
    let scanDate = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!

    private func name(_ format: FileNameFormat, _ name: String) -> String {
        format.fileName(name: name, documentDate: date, scanDate: scanDate)
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
        #expect(FileNameFormat(datePosition: .start).fileName(name: "Lumen", documentDate: nil, scanDate: scanDate) == "2026-11-16 Lumen")
    }

    @Test func keepsAccents() {
        #expect(name(FileNameFormat(separator: .dash, lowercase: true), "Bénéficiaires effectifs") == "bénéficiaires-effectifs")
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

    @Test func turnsTheFormerDateFirstSwitchIntoADateAtTheStart() throws {
        let decoder = JSONDecoder()
        let legacy = try decoder.decode(FileNameFormat.self, from: Data(#"{"datePrefix":true,"separator":"dash","lowercase":true}"#.utf8))
        #expect(legacy == FileNameFormat(datePosition: .start, separator: .dash, lowercase: true))
        let format = FileNameFormat(datePosition: .end, dateStyle: .month, dateSource: .scan, separator: .underscore, lowercase: true)
        #expect(try decoder.decode(FileNameFormat.self, from: JSONEncoder().encode(format)) == format)
    }
}
