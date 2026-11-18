import CoreImage
import Foundation
import PDFKit
import ScannerKit
import ScannerKitTesting
import Synchronization
import Testing

final class ScanProcessorTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ScanProcessorTests-\(UUID().uuidString)")
    lazy var store = ScanStore(scansDirectory: root.appending(path: "Scans"), documentsDirectory: root.appending(path: "Documents"))
    lazy var processor = ScanProcessor(store: store, paper: .a4)

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

    @Test func takesTheLiveOutlineWhenNoPageIsFoundOnThePhoto() async throws {
        let scanID = UUID()
        let pending = PendingPage(liveQuad: .tilted)
        try store.savePhoto(PageExtractor(context: CIContext()).jpegData(of: SyntheticPhoto.render(page: nil), quality: 0.9)!, scanID: scanID, pageID: pending.id)
        let page = try await processor.addPage(pending, scanID: scanID)
        #expect(page.quad == .tilted)
        #expect(page.detectedQuad == .tilted)
        let flat = try #require(CIImage(contentsOf: store.flatURL(scanID: scanID, page: page)))
        #expect(flat.extent.size != SyntheticPhoto.size)
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

    @Test func readsAPageOnceForTheDetailsAndThePDFEvenAfterARelaunch() async throws {
        var scan = Scan(name: "Invoice")
        let page = try addFlatPage(to: &scan)
        let reads = Reads()
        let processor = ScanProcessor(store: store, paper: .a4, readText: reads.read)

        _ = try await processor.detectDocument(on: page, scanID: scan.id)
        _ = try await processor.pdfData(of: scan)
        #expect(reads.count == 1)
        let relaunched = ScanProcessor(store: store, paper: .a4, readText: reads.read)
        _ = try await relaunched.detectDocument(on: page, scanID: scan.id)
        _ = try await relaunched.pdfData(of: scan)
        #expect(reads.count == 1)
    }

    @Test func readsAPageAgainOnlyOnceCutOrTurnedDifferently() async throws {
        var scan = Scan(name: "Invoice")
        var page = try addFlatPage(to: &scan)
        let reads = Reads()
        let processor = ScanProcessor(store: store, paper: .a4, readText: reads.read)
        _ = try await processor.pdfData(of: scan)

        page.cleanup.look = .color
        page.revision += 1
        scan.pages = [page]
        _ = try await processor.pdfData(of: scan)
        #expect(reads.count == 1)

        page.rotate()
        page.revision += 1
        scan.pages = [page]
        _ = try await processor.pdfData(of: scan)
        #expect(reads.count == 2)

        let flat = try Data(contentsOf: store.flatURL(scanID: scan.id, page: page))
        page.crop += 1
        page.revision += 1
        try flat.write(to: store.flatURL(scanID: scan.id, page: page))
        scan.pages = [page]
        _ = try await processor.pdfData(of: scan)
        #expect(reads.count == 3)
    }

    @Test func readsAPageAgainWhenReadingItFailed() async throws {
        var scan = Scan(name: "Invoice")
        _ = try addFlatPage(to: &scan)
        let reads = Reads(failures: 1)
        let processor = ScanProcessor(store: store, paper: .a4, readText: reads.read)

        await #expect(throws: Reads.Failure.self) { try await processor.pdfData(of: scan) }
        let document = try #require(PDFDocument(data: try await processor.pdfData(of: scan)))
        #expect(document.string?.contains("Read 2") == true)
        _ = try await ScanProcessor(store: store, paper: .a4, readText: reads.read).pdfData(of: scan)
        #expect(reads.count == 2)
    }

    @Test func writesTheTextLayerOfAPageReadBeforeAsWhenReadNow() async throws {
        var scan = Scan(name: "Invoice")
        _ = try addFlatPage(to: &scan)
        let read = try await processor.pdfData(of: scan)
        let kept = try await ScanProcessor(store: store, paper: .a4, readText: { _ in throw Reads.Failure() }).pdfData(of: scan)
        #expect(try contentStream(ofFirstPageOf: kept) == contentStream(ofFirstPageOf: read))
        #expect(try contentStream(ofFirstPageOf: read).count > 1000)
    }

    @Test func deletesTheTextOfAPageWithItsFiles() async throws {
        var scan = Scan(name: "Invoice")
        let page = try addFlatPage(to: &scan)
        _ = try await ScanProcessor(store: store, paper: .a4, readText: Reads().read).pdfData(of: scan)
        let files = { [store] in try FileManager.default.contentsOfDirectory(atPath: store.directory(of: scan.id).path(percentEncoded: false)) }
        #expect(try files().count == 2)

        store.deletePageFiles(scanID: scan.id, pageID: page.id)
        #expect(try files().isEmpty)
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

    @Test func stopsMakingThePDFWhenCancelledBetweenTwoPages() async throws {
        var scan = Scan(name: "Invoice")
        _ = try addFlatPage(to: &scan)
        _ = try addFlatPage(to: &scan)
        let reads = Reads()
        let processor = ScanProcessor(store: store, paper: .a4) { page in
            withUnsafeCurrentTask { $0?.cancel() }
            return try reads.read(page)
        }
        let pdf = Task { [scan] in try await processor.pdfData(of: scan) }

        await #expect(throws: CancellationError.self) { try await pdf.value }
        #expect(reads.count == 1)
    }

    @Test func detectsTheDocumentFromTheTextOfThePage() async throws {
        var scan = Scan(name: "Invoice")
        let page = try addFlatPage(SyntheticPage(title: "INVOICE"), to: &scan)
        let document = try #require(try await processor.detectDocument(on: page, scanID: scan.id))
        #expect(document.details.category == .invoice)
        #expect(document.parts.type == "Invoice")
    }

    /// Stores the flat page of a new page of the scan.
    private func addFlatPage(_ synthetic: SyntheticPage = SyntheticPage(), to scan: inout Scan) throws -> ScanPage {
        let page = ScanPage(quad: nil, analysis: .sample)
        try FileManager.default.createDirectory(at: store.directory(of: scan.id), withIntermediateDirectories: true)
        try #require(PageExtractor(context: CIContext()).jpegData(of: synthetic.render(), quality: 0.9)).write(to: store.flatURL(scanID: scan.id, page: page))
        scan.pages.append(page)
        return page
    }

    private func contentStream(ofFirstPageOf data: Data) throws -> Data {
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        defer { withExtendedLifetime(document) {} }
        var contents: CGPDFStreamRef?, format = CGPDFDataFormat.raw
        #expect(CGPDFDictionaryGetStream(try #require(document.page(at: 1)?.dictionary), "Contents", &contents))
        return try #require(contents.flatMap { CGPDFStreamCopyData($0, &format) }) as Data
    }
}

/// Counts the readings of the page text, and makes up the lines read.
private final class Reads: Sendable {
    struct Failure: Error {}
    private let state: Mutex<(count: Int, failures: Int)>

    /// Fails the first `failures` readings.
    init(failures: Int = 0) {
        state = Mutex((0, failures))
    }

    var count: Int { state.withLock(\.count) }

    @Sendable func read(_ page: CIImage) throws -> [TextLine] {
        let (count, fails) = state.withLock { state in
            state.count += 1
            return (state.count, state.count <= state.failures)
        }
        if fails { throw Failure() }
        return [TextLine(text: "Read \(count)", frame: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02))]
    }
}
