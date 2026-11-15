import CoreImage
import Foundation
import PDFKit
import ScannerKit
import ScannerKitTesting
import Testing

final class ScanProcessorTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ScanProcessorTests-\(UUID().uuidString)")
    lazy var store = ScanStore(scansDirectory: root.appending(path: "Scans"), documentsDirectory: root.appending(path: "Documents"))
    lazy var processor = ScanProcessor(store: store, context: CIContext())

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func processesAPhotoIntoAPageAndAPDF() throws {
        var scan = Scan(name: "Test")
        let page = try processor.addPage(photo: SyntheticPhoto.jpeg(), liveQuad: nil, scanID: scan.id, look: nil)
        #expect(try #require(page.quad).maxCornerDistance(to: .tilted) < 0.02)
        for url in [store.photoURL(scanID: scan.id, pageID: page.id), store.flatURL(scanID: scan.id, pageID: page.id), store.previewURL(scanID: scan.id, pageID: page.id)] {
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }

        scan.pages = [page, page]
        let document = try #require(PDFDocument(data: try processor.pdfData(of: scan, quality: .small, paper: .a4)))
        #expect(document.pageCount == 2)
    }

    @Test func recropsFromTheOriginalPhoto() throws {
        let scanID = UUID()
        let page = try processor.addPage(photo: SyntheticPhoto.jpeg(), liveQuad: nil, scanID: scanID, look: nil)

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

    @Test func suggestsNamesFromTheTextOfThePreview() throws {
        let scanID = UUID()
        let page = ScanPage(quad: nil, analysis: .sample)
        try FileManager.default.createDirectory(at: store.directory(of: scanID), withIntermediateDirectories: true)
        try processor.writePreview(of: page, scanID: scanID, flat: SyntheticPage().render())
        let suggestions = try #require(processor.nameSuggestions(for: page, scanID: scanID, date: .now))
        #expect(suggestions.names.first?.hasPrefix("Invoice") == true)
    }
}
