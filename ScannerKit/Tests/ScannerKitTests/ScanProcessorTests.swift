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
        for url in [store.photoURL(scanID: scan.id, pageID: page.id), store.flatURL(scanID: scan.id, page: page), store.previewURL(scanID: scan.id, pageID: page.id)] {
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
        let flat = try #require(CIImage(contentsOf: store.flatURL(scanID: scanID, page: whole)))
        #expect(flat.extent.size == SyntheticPhoto.size)

        let half = Quad.rect(x: 0, y: 0, width: 1, height: 0.5)
        let halved = try await processor.recrop(whole, scanID: scanID, quad: half)
        #expect(halved.quad == half)
        let cropped = try #require(CIImage(contentsOf: store.flatURL(scanID: scanID, page: halved)))
        #expect(abs(cropped.extent.height / cropped.extent.width - 800.0 / 1200) < 0.02)
    }

    @Test func recropKeepsTheFlatPageItReplaces() async throws {
        let scanID = UUID()
        let page = try await addPage(scanID: scanID)
        let flat = try Data(contentsOf: store.flatURL(scanID: scanID, page: page))

        let whole = try await processor.recrop(page, scanID: scanID, quad: nil)
        #expect(store.flatURL(scanID: scanID, page: whole) != store.flatURL(scanID: scanID, page: page))
        #expect(try Data(contentsOf: store.flatURL(scanID: scanID, page: page)) == flat)
    }

    @Test func keepsTheEdgesOfTheWhitePreviewOfAWhitePageWhite() throws {
        let scanID = UUID()
        let page = ScanPage(quad: nil, analysis: .sample)
        try FileManager.default.createDirectory(at: store.directory(of: scanID), withIntermediateDirectories: true)
        try processor.writePreview(of: page, scanID: scanID, flat: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1001, height: 1415)))
        let preview = try #require(CIImage(contentsOf: store.previewURL(scanID: scanID, pageID: page.id)))
        let width = Int(preview.extent.width), height = Int(preview.extent.height)
        #expect(height == 1200)
        var pixels = [UInt8](repeating: 0, count: width * height)
        CIContext().render(preview, toBitmap: &pixels, rowBytes: width, bounds: preview.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        let edges = edgePixels(of: pixels, width: width, height: height)
        #expect(edges.allSatisfy { $0 == 255 }, "darkest edge pixel \(edges.min() ?? 0)")
    }

    @Test func makesThePDFSearchableWithTheTextOfThePages() async throws {
        var scan = Scan(name: "Invoice")
        let page = ScanPage(quad: nil, analysis: .sample)
        try FileManager.default.createDirectory(at: store.directory(of: scan.id), withIntermediateDirectories: true)
        try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage().render(), quality: 0.9)).write(to: store.flatURL(scanID: scan.id, page: page))
        scan.pages = [page]

        let document = try #require(PDFDocument(data: try await processor.pdfData(of: scan)))
        #expect(document.string?.contains("The quick brown fox jumps over the lazy dog") == true)
    }

    @Test func readsTheTextOfAPageAgainWhenReadingItFailed() async throws {
        var scan = Scan(name: "Invoice")
        let page = ScanPage(quad: nil, analysis: .sample)
        try FileManager.default.createDirectory(at: store.directory(of: scan.id), withIntermediateDirectories: true)
        try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage().render(), quality: 0.9)).write(to: store.flatURL(scanID: scan.id, page: page))
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
        try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(lines: 5).render(), quality: 0.9)).write(to: store.flatURL(scanID: scan.id, page: page))
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
