import Foundation
import ScannerKit
import ScannerKitTesting
import Testing

final class ScanStoreTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ScanStoreTests-\(UUID().uuidString)")
    lazy var store = ScanStore(scansDirectory: root.appending(path: "Scans"), documentsDirectory: root.appending(path: "Documents"))

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Documents"), withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func savesAndLoadsScansNewestFirst() throws {
        var old = Scan(created: Date(timeIntervalSinceNow: -100), name: "Old")
        old.pages = [ScanPage(quad: nil, analysis: .sample)]
        let new = Scan(name: "New")
        try store.save(old)
        try store.save(new)
        #expect(store.all().map(\.name) == ["New", "Old"])
        #expect(store.all().last?.pages == old.pages)
    }

    @Test func countsTheBytesOfScansAndTheirPDFs() throws {
        let scan = Scan(name: "Invoice")
        try store.save(scan)
        let json = store.byteCount()
        #expect(json > 0)
        try Data(count: 1000).write(to: store.pdfURL(of: scan))
        try Data(count: 500).write(to: root.appending(path: "Documents/Other.pdf"))
        #expect(store.byteCount() == json + 1000)
    }

    @Test func picksAnAvailableName() throws {
        let scans = [Scan(name: "Invoice")]
        try Data().write(to: root.appending(path: "Documents/Receipt.pdf"))
        try Data().write(to: root.appending(path: "Documents/Lumen invoice.pdf"))
        let scan = Scan(name: "Scan")
        #expect(store.availableName("Lumen invoice", for: scan, among: scans) == "Lumen invoice 2")
        #expect(store.availableName("Invoice", for: scan, among: scans) == "Invoice 2")
        #expect(store.availableName("invoice", for: scan, among: scans) == "invoice 2")
        #expect(store.availableName("Receipt", for: scan, among: scans) == "Receipt 2")
        #expect(store.availableName("Letter", for: scan, among: scans) == "Letter")
        #expect(store.availableName("Invoice", for: scan, among: scans, separator: "-") == "Invoice-2")
    }

    @Test func handlesNamesAndFoldersWithSpaces() throws {
        let store = ScanStore(scansDirectory: root.appending(path: "Application Support/Scans"), documentsDirectory: root.appending(path: "Documents"))
        var scan = Scan(name: "Lumen invoice")
        try store.save(scan)
        try Data("%PDF".utf8).write(to: store.pdfURL(of: scan))
        #expect(store.availableName("Lumen invoice", for: Scan(name: "Other"), among: [scan]) == "Lumen invoice 2")
        scan.name = "Lumen invoice November"
        store.movePDF(from: "Lumen invoice", to: scan)
        #expect(FileManager.default.fileExists(atPath: store.pdfURL(of: scan).path(percentEncoded: false)))
        #expect(store.all().count == 1)
    }

    @Test func keepsItsOwnName() throws {
        let scan = Scan(name: "Invoice")
        try store.save(scan)
        try Data().write(to: store.pdfURL(of: scan))
        #expect(store.availableName("Invoice", for: scan, among: [scan]) == "Invoice")
    }

    @Test func movesThePDFWhenRenamed() throws {
        var scan = Scan(name: "Scan")
        try Data("%PDF".utf8).write(to: store.pdfURL(of: scan))
        scan.name = "Invoice"
        store.movePDF(from: "Scan", to: scan)
        #expect(FileManager.default.fileExists(atPath: store.pdfURL(of: scan).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Documents/Scan.pdf").path(percentEncoded: false)))
    }

    @Test func deletesThePDFItCannotMoveRatherThanLeaveItUnderItsOldName() throws {
        var scan = Scan(name: "Scan")
        try Data("%PDF".utf8).write(to: store.pdfURL(of: scan))
        scan.name = "Invoice"
        let locked = store.pdfURL(of: scan).path(percentEncoded: false)
        try Data().write(to: store.pdfURL(of: scan))
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: locked) }

        store.movePDF(from: "Scan", to: scan)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Documents/Scan.pdf").path(percentEncoded: false)))
    }

    @Test func keepsLocalPDFsOutOfTheFoldersOfTheName() throws {
        var scan = Scan(name: "Scan")
        try Data("%PDF".utf8).write(to: store.pdfURL(of: scan))
        scan.name = "Invoice/2026 Lumen"
        store.movePDF(from: "Scan", to: scan)
        #expect(store.pdfURL(of: scan) == root.appending(path: "Documents/2026 Lumen.pdf"))
        #expect(FileManager.default.fileExists(atPath: store.pdfURL(of: scan).path(percentEncoded: false)))
    }

    @Test func numbersATakenFileNameInsideItsFolders() throws {
        #expect(store.availableName("Invoice/2026 Lumen", for: Scan(name: "Scan"), among: [Scan(name: "Receipt/2026 Lumen")]) == "Invoice/2026 Lumen 2")
    }
}
