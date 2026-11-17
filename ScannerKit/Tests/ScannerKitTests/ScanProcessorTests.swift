import CoreImage
import Foundation
import PDFKit
import ScannerKit
import ScannerKitTesting
import Testing

final class ScanProcessorTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ScanProcessorTests-\(UUID().uuidString)")
    lazy var store = ScanStore(scansDirectory: root.appending(path: "Scans"), documentsDirectory: root.appending(path: "Documents"))
    lazy var processor = ScanProcessor(store: store, context: CIContext(), paper: .a4)

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func addPage(scanID: UUID) async throws -> ScanPage {
        let pending = PendingPage(liveQuad: nil)
        try store.savePhoto(SyntheticPhoto.jpeg(), scanID: scanID, pageID: pending.id)
        return try await processor.addPage(pending, scanID: scanID)
    }

    @Test func processesAPhotoIntoAPageAndAPDF() async throws {
        var scan = Scan(name: "Test")
        let page = try await addPage(scanID: scan.id)
        #expect(try #require(page.quad).maxCornerDistance(to: .tilted) < 0.02)
        for url in [store.photoURL(scanID: scan.id, pageID: page.id), store.flatURL(scanID: scan.id, pageID: page.id), store.previewURL(scanID: scan.id, pageID: page.id)] {
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }

        scan.pages = [page, page]
        let document = try #require(PDFDocument(data: try await processor.pdfData(of: scan)))
        #expect(document.pageCount == 2)
    }

    @Test func recropsFromTheOriginalPhoto() async throws {
        let scanID = UUID()
        let page = try await addPage(scanID: scanID)

        let whole = try await processor.recrop(page, scanID: scanID, quad: nil)
        #expect(whole.quad == nil)
        #expect(whole.detectedQuad == page.quad)
        let flat = try #require(CIImage(contentsOf: store.flatURL(scanID: scanID, pageID: page.id)))
        #expect(flat.extent.size == SyntheticPhoto.size)

        let half = Quad.rect(x: 0, y: 0, width: 1, height: 0.5)
        #expect(try await processor.recrop(whole, scanID: scanID, quad: half).quad == half)
        let cropped = try #require(CIImage(contentsOf: store.flatURL(scanID: scanID, pageID: page.id)))
        #expect(abs(cropped.extent.height / cropped.extent.width - 800.0 / 1200) < 0.02)
    }

    @Test func makesThePDFSearchableWithTheTextOfThePages() async throws {
        var scan = Scan(name: "Invoice")
        let page = ScanPage(quad: nil, analysis: .sample)
        try FileManager.default.createDirectory(at: store.directory(of: scan.id), withIntermediateDirectories: true)
        try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage().render(), quality: 0.9)).write(to: store.flatURL(scanID: scan.id, pageID: page.id))
        scan.pages = [page]

        let document = try #require(PDFDocument(data: try await processor.pdfData(of: scan)))
        #expect(document.string?.contains("The quick brown fox jumps over the lazy dog") == true)
    }

    @Test func readsTheTextOfAPageAgainWhenReadingItFailed() async throws {
        var scan = Scan(name: "Invoice")
        let page = ScanPage(quad: nil, analysis: .sample)
        try FileManager.default.createDirectory(at: store.directory(of: scan.id), withIntermediateDirectories: true)
        try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage().render(), quality: 0.9)).write(to: store.flatURL(scanID: scan.id, pageID: page.id))
        scan.pages = [page]
        let processor = processor, failing = scan

        await #expect(throws: (any Error).self) { try await inCancelledTask { try await processor.pdfData(of: failing) } }
        let document = try #require(PDFDocument(data: try await processor.pdfData(of: scan)))
        #expect(document.string?.contains("The quick brown fox jumps over the lazy dog") == true)
    }

    @Test func stopsMakingThePDFWhenCancelled() async throws {
        var scan = Scan(name: "Invoice")
        let page = ScanPage(quad: nil, analysis: .sample)
        try FileManager.default.createDirectory(at: store.directory(of: scan.id), withIntermediateDirectories: true)
        try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(lines: 5).render(), quality: 0.9)).write(to: store.flatURL(scanID: scan.id, pageID: page.id))
        scan.pages = [page]
        let processor = processor, cancelled = scan
        _ = try await processor.pdfData(of: scan)

        await #expect(throws: CancellationError.self) { try await inCancelledTask { try await processor.pdfData(of: cancelled) } }
    }

    @Test func detectsTheDocumentFromTheTextOfThePreview() async throws {
        let scanID = UUID()
        let page = ScanPage(quad: nil, analysis: .sample)
        try FileManager.default.createDirectory(at: store.directory(of: scanID), withIntermediateDirectories: true)
        try processor.writePreview(of: page, scanID: scanID, flat: SyntheticPage(title: "INVOICE").render())
        let document = try #require(try await processor.detectDocument(on: page, scanID: scanID))
        #expect(document.details.category == .invoice)
        #expect(document.parts.type == "Invoice")
    }
}
