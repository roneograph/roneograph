import Foundation
import ScannerKit
import ScannerKitTesting
import Testing

struct NamePatternTests {
    private func date(_ iso: String) -> Date {
        .day(iso)
    }

    private func next(_ name: String, from first: String, number: String? = nil, to second: String, nextNumber: String? = nil) -> String {
        NamePattern(name: name, details: DocumentDetails(number: number), date: date(first)).name(details: DocumentDetails(number: nextNumber), date: date(second))
    }

    @Test func keepsTypedTextAsTyped() {
        #expect(next("Lumen bill", from: "2026-11-12", to: "2026-12-10") == "Lumen bill")
    }

    @Test func followsTheMonthAndYearOfTheDocument() {
        #expect(next("Lumen electricity November 2026", from: "2026-11-12", to: "2026-12-10") == "Lumen electricity December 2026")
        #expect(next("Lumen electricity october", from: "2026-11-12", to: "2027-01-08") == "Lumen electricity december")
        #expect(next("Lumen electricity October 2026", from: "2026-11-12", to: "2027-01-08") == "Lumen electricity December 2026")
        #expect(next("Électricité (octobre)", from: "2026-11-12", to: "2026-12-10") == "Électricité (novembre)")
        #expect(next("Strom OKTOBER", from: "2026-11-12", to: "2026-12-10") == "Strom NOVEMBER")
        #expect(next("Luz noviembre", from: "2026-11-12", to: "2026-12-10") == "Luz diciembre")
    }

    @Test func followsShortMonthNamesWithoutTheirDot() {
        #expect(next("Lumen Nov. 2026", from: "2026-11-12", to: "2027-11-10") == "Lumen Nov 2027")
        #expect(next("Strom Okt. 2026", from: "2026-10-12", to: "2026-11-10") == "Strom Nov 2026")
    }

    @Test func tellsWhatFollowsTheNextDocument() {
        let typed = NamePattern(name: "Lumen bill", details: DocumentDetails(number: "2026-1142"), date: date("2026-11-12"))
        #expect(!typed.follows.date && !typed.follows.number)
        let dated = NamePattern(name: "Lumen November", details: DocumentDetails(number: "2026-1142"), date: date("2026-11-12"))
        #expect(dated.follows.date && !dated.follows.number)
        let numbered = NamePattern(name: "Lumen 2026-1142", details: DocumentDetails(number: "2026-1142"), date: date("2026-11-12"))
        #expect(!numbered.follows.date && numbered.follows.number)
    }

    @Test func followsNumericDates() {
        #expect(next("2026-11-12 Lumen", from: "2026-11-12", to: "2026-12-10") == "2026-12-10 Lumen")
        #expect(next("Lumen 2026-10", from: "2026-11-12", to: "2026-12-10") == "Lumen 2026-11")
        #expect(next("Tax notice 2025", from: "2026-08-30", to: "2027-08-29") == "Tax notice 2026")
        #expect(next("Lumen 2026-10-01", from: "2026-11-12", to: "2026-12-10") == "Lumen 2026-10-01")
    }

    @Test func followsTheNumberAndDropsItWhenThereIsNone() {
        #expect(next("Lumen 2026-1142", from: "2026-11-12", number: "2026-1142", to: "2026-12-10", nextNumber: "2026-1287") == "Lumen 2026-1287")
        #expect(next("Lumen 2026-1142 paid", from: "2026-11-12", number: "2026-1142", to: "2026-12-10") == "Lumen paid")
    }

    @Test func survivesBeingSaved() throws {
        let pattern = NamePattern(name: "Lumen October 2026 #2026-1142", details: DocumentDetails(number: "2026-1142"), date: date("2026-11-12"))
        #expect(try JSONDecoder().decode(NamePattern.self, from: JSONEncoder().encode(pattern)) == pattern)
    }
}
