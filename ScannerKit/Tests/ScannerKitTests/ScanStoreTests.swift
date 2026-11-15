import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PDFKit
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

    @Test func deletesExpiredScansWithTheirPDF() throws {
        let old = Scan(created: Date(timeIntervalSinceNow: -8 * 86400), name: "Old")
        let recent = Scan(created: Date(timeIntervalSinceNow: -6 * 86400), name: "Recent")
        for scan in [old, recent] {
            try store.save(scan)
            try Data("%PDF".utf8).write(to: store.pdfURL(of: scan))
        }
        store.deleteScans(olderThan: Date(timeIntervalSinceNow: -7 * 86400))
        #expect(store.all().map(\.name) == ["Recent"])
        #expect(!FileManager.default.fileExists(atPath: store.pdfURL(of: old).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: store.pdfURL(of: recent).path(percentEncoded: false)))
    }

    @Test func picksAnAvailableName() throws {
        try store.save(Scan(name: "Invoice"))
        try Data().write(to: root.appending(path: "Documents/Receipt.pdf"))
        try Data().write(to: root.appending(path: "Documents/Lumen invoice.pdf"))
        let scan = Scan(name: "Scan")
        #expect(store.availableName("Lumen invoice", for: scan) == "Lumen invoice 2")
        #expect(store.availableName("Invoice", for: scan) == "Invoice 2")
        #expect(store.availableName("invoice", for: scan) == "invoice 2")
        #expect(store.availableName("Receipt", for: scan) == "Receipt 2")
        #expect(store.availableName("Letter", for: scan) == "Letter")
        #expect(store.availableName("Invoice", for: scan, separator: "-") == "Invoice-2")
    }

    @Test func handlesNamesAndFoldersWithSpaces() throws {
        let store = ScanStore(scansDirectory: root.appending(path: "Application Support/Scans"), documentsDirectory: root.appending(path: "Documents"))
        var scan = Scan(name: "Lumen invoice")
        try store.save(scan)
        try Data("%PDF".utf8).write(to: store.pdfURL(of: scan))
        #expect(store.availableName("Lumen invoice", for: Scan(name: "Other")) == "Lumen invoice 2")
        scan.name = "Lumen invoice November"
        store.movePDF(from: "Lumen invoice", to: scan)
        #expect(FileManager.default.fileExists(atPath: store.pdfURL(of: scan).path(percentEncoded: false)))
        #expect(store.all().count == 1)
    }

    @Test func keepsItsOwnName() throws {
        let scan = Scan(name: "Invoice")
        try store.save(scan)
        try Data().write(to: store.pdfURL(of: scan))
        #expect(store.availableName("Invoice", for: scan) == "Invoice")
    }

    @Test func movesThePDFWhenRenamed() throws {
        var scan = Scan(name: "Scan")
        try Data("%PDF".utf8).write(to: store.pdfURL(of: scan))
        scan.name = "Invoice"
        store.movePDF(from: "Scan", to: scan)
        #expect(FileManager.default.fileExists(atPath: store.pdfURL(of: scan).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Documents/Scan.pdf").path(percentEncoded: false)))
    }

    @Test func processesAPhotoIntoAPageAndAPDF() throws {
        let context = CIContext()
        let processor = ScanProcessor(store: store, context: context)
        let quad = Quad(topLeft: CGPoint(x: 0.22, y: 0.18), topRight: CGPoint(x: 0.8, y: 0.21), bottomRight: CGPoint(x: 0.86, y: 0.82), bottomLeft: CGPoint(x: 0.14, y: 0.8))
        let photo = try #require(PageExtractor(context: context).jpegData(of: SyntheticPhoto.render(page: quad), quality: 0.9))
        var scan = Scan(name: "Test")

        let page = try processor.addPage(photo: photo, liveQuad: nil, scanID: scan.id, look: nil)
        #expect(try #require(page.quad).maxCornerDistance(to: quad) < 0.02)
        for url in [store.photoURL(scanID: scan.id, pageID: page.id), store.flatURL(scanID: scan.id, pageID: page.id), store.previewURL(scanID: scan.id, pageID: page.id)] {
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }

        scan.pages = [page, page]
        let document = try #require(PDFDocument(data: try processor.pdfData(of: scan, quality: .small, paper: .a4)))
        #expect(document.pageCount == 2)
    }

    @Test func recropsFromTheOriginalPhoto() throws {
        let context = CIContext()
        let processor = ScanProcessor(store: store, context: context)
        let quad = Quad(topLeft: CGPoint(x: 0.22, y: 0.18), topRight: CGPoint(x: 0.8, y: 0.21), bottomRight: CGPoint(x: 0.86, y: 0.82), bottomLeft: CGPoint(x: 0.14, y: 0.8))
        let photo = try #require(PageExtractor(context: context).jpegData(of: SyntheticPhoto.render(page: quad), quality: 0.9))
        let scanID = UUID()
        let page = try processor.addPage(photo: photo, liveQuad: nil, scanID: scanID, look: nil)

        let whole = try processor.recrop(page, scanID: scanID, quad: nil)
        #expect(whole.quad == nil)
        #expect(whole.detectedQuad == page.quad)
        let flat = try #require(CIImage(contentsOf: store.flatURL(scanID: scanID, pageID: page.id)))
        #expect(flat.extent.size == SyntheticPhoto.size)

        let half = Quad.rect(x: 0, y: 0, width: 1, height: 0.5)
        #expect(try processor.recrop(whole, scanID: scanID, quad: half).quad == half)
        let cropped = try #require(CIImage(contentsOf: store.flatURL(scanID: scanID, pageID: page.id)))
        #expect(abs(cropped.extent.height / cropped.extent.width - 800.0 / 1200) < 0.02)
    }

    @Test func rotatesAPageAQuarterTurnClockwise() throws {
        let context = CIContext()
        let cleaner = PageCleaner(context: context)
        let flat = SyntheticPage().render()
        var page = ScanPage(quad: nil, analysis: cleaner.analyze(flat))
        page.rotate(clockwise: true)
        let turned = cleaner.render(flat, analysis: page.analysis, settings: page.cleanup)
        #expect(turned.extent.width > turned.extent.height)
        #expect(cleaner.analyze(turned).orientation == .left)
        #expect(page.revision == 1)
    }
}

final class ScannerSettingsTests {
    @Test func keepsDefaultsForMissingOrUnknownValues() throws {
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(#"{"email":"me@example.com","quality":"huge"}"#.utf8))
        #expect(settings.email == "me@example.com")
        #expect(settings.quality == .balanced)
        #expect(settings.paper == .a4)
        #expect(settings.autoCapture)
    }

    @Test(arguments: [("me@example.com", true), ("me@example", false), ("", false), ("a b@example.com", false), ("me@example.c", false)])
    func validatesEmails(email: String, valid: Bool) {
        #expect(ScannerSettings.isValidEmail(email) == valid)
    }
}

extension PageAnalysis {
    static let sample = PageAnalysis(orientation: .up, skewDegrees: 0, suggestedLook: .gray, colorFraction: 0, pictureFraction: 0, textLineHeight: 0.0125)
}
