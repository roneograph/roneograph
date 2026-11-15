import CoreImage
import Foundation
import ScannerKit
import ScannerKitTesting
@testable import ScannerModels
import Testing

/// A temporary scan store, settings and processor, removed after each test.
@MainActor
final class Fixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "ScannerModelsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let store: ScanStore
    let settings: SettingsStore
    let processor: ScanProcessor
    let defaults: UserDefaults
    private let suite = "ScannerModelsTests-\(UUID().uuidString)"

    init() throws {
        store = ScanStore(scansDirectory: root.appending(path: "Application Support/Scans"), documentsDirectory: root.appending(path: "Documents"))
        try FileManager.default.createDirectory(at: store.documentsDirectory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)!
        settings = SettingsStore(defaults: defaults)
        processor = ScanProcessor(store: store, context: CIContext())
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func scanModel(title: String = "Scan 2026-11-15") -> ScanModel {
        let model = ScanModel(scan: Scan(name: "", title: title), processor: processor, settings: settings)
        model.applyFileName()
        return model
    }

    /// A scan with pages already processed.
    func scanModel(pages: Int) async -> ScanModel {
        let model = scanModel()
        for _ in 0..<pages { model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil) }
        await model.waitUntilIdle()
        return model
    }

    func pdfExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: store.documentsDirectory.appending(path: "\(name).pdf").path(percentEncoded: false))
    }
}

@MainActor
@Suite(.serialized)
struct ScanModelTests {
    @Test func addsPagesInCaptureOrderAndSavesThem() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.addPhoto(SyntheticPhoto.jpeg(page: .rect(x: 0.2, y: 0.1, width: 0.6, height: 0.6)), liveQuad: nil)
        #expect(model.processing == 2)
        await model.waitUntilIdle()

        #expect(model.processing == 0)
        #expect(model.scan.pages.count == 2)
        #expect(model.scan.pages[1].quad.map { $0.maxCornerDistance(to: .rect(x: 0.2, y: 0.1, width: 0.6, height: 0.6)) < 0.02 } == true)
        #expect(fixture.store.all().first?.pages == model.scan.pages)
    }

    @Test func emptyScansAreNeverSaved() throws {
        let fixture = try Fixture()
        _ = fixture.scanModel()
        #expect(fixture.store.all().isEmpty)
    }

    @Test func movesAPageToThePlaceOfAnother() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 3)
        let ids = model.scan.pages.map(\.id)

        model.movePage(ids[0], to: ids[2])
        #expect(model.scan.pages.map(\.id) == [ids[1], ids[2], ids[0]])
        model.movePage(ids[0], to: ids[1])
        #expect(model.scan.pages.map(\.id) == [ids[0], ids[1], ids[2]])
        model.movePage(ids[1], to: ids[1])
        #expect(model.scan.pages.map(\.id) == ids)
        #expect(fixture.store.all().first?.pages.map(\.id) == ids)
    }

    @Test func deletesAPageAndItsFiles() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 2)
        let page = model.scan.pages[0]
        model.deletePage(page.id)
        #expect(model.scan.pages.count == 1)
        #expect(!FileManager.default.fileExists(atPath: model.photoURL(of: page).path(percentEncoded: false)))
    }

    @Test func quickEditsAreAllApplied() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        let id = model.scan.pages[0].id
        let orientation = model.scan.pages[0].analysis.orientation

        model.rotatePage(id, clockwise: true)
        model.rotatePage(id, clockwise: true)
        model.setLook(.blackAndWhite, of: [id])
        await model.waitUntilIdle()

        let page = model.scan.pages[0]
        var expected = ScanPage(quad: nil, analysis: page.analysis)
        expected.analysis.orientation = orientation
        expected.rotate(clockwise: true)
        expected.rotate(clockwise: true)
        #expect(page.analysis.orientation == expected.analysis.orientation)
        #expect(page.cleanup.look == .blackAndWhite)
        #expect(page.revision == 3)
        #expect(model.updating == 0)
    }

    @Test func recropsAPage() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        let page = model.scan.pages[0]

        model.recrop(page.id, quad: nil)
        await model.waitUntilIdle()
        #expect(model.scan.pages[0].quad == nil)
        #expect(model.scan.pages[0].detectedQuad == page.quad)
        #expect(model.scan.pages[0].revision == page.revision + 1)

        model.recrop(page.id, quad: page.detectedQuad)
        await model.waitUntilIdle()
        #expect(model.scan.pages[0].quad == page.quad)
    }

    @Test func deletingWhilePagesAreProcessedLeavesNothingBehind() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.delete()
        await model.waitUntilIdle()
        try await Task.sleep(for: .milliseconds(100))

        #expect(fixture.store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.directory(of: model.id).path(percentEncoded: false)))
    }

    @Test func renameUsesTheFileNameFormatAndMovesThePDF() async throws {
        let fixture = try Fixture()
        fixture.settings.value.fileNameFormat = FileNameFormat(datePrefix: true, separator: .dash, lowercase: true)
        let model = await fixture.scanModel(pages: 1)
        await model.buildPDF(delay: .zero)
        let first = model.scan.name
        #expect(fixture.pdfExists(first))

        model.rename("Lumen Energy invoice")
        #expect(model.scan.title == "Lumen Energy invoice")
        #expect(model.scan.isNamedByUser)
        #expect(model.scan.name == "\(FileNamer.isoDate(model.scan.fileDate))-lumen-energy-invoice")
        #expect(fixture.pdfExists(model.scan.name))
        #expect(!fixture.pdfExists(first))
    }

    @Test func anEmptyNameFallsBack() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.rename("   ")
        #expect(model.scan.title == (model.scan.suggestions.first ?? model.fallbackTitle))
    }

    @Test func twoScansWithTheSameNameGetDifferentFiles() async throws {
        let fixture = try Fixture()
        fixture.settings.value.fileNameFormat = FileNameFormat(separator: .dash)
        let first = await fixture.scanModel(pages: 1)
        let second = await fixture.scanModel(pages: 1)
        first.rename("Invoice")
        second.rename("Invoice")
        #expect(first.scan.name == "Invoice")
        #expect(second.scan.name == "Invoice-2")
    }

    @Test func aRenameIsNotReplacedBySuggestions() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.rename("Mine")
        await model.waitUntilIdle()
        #expect(model.scan.title == "Mine")
    }

    @Test func changingTheFormatRenamesTheFile() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.rename("Lumen invoice")
        fixture.settings.value.fileNameFormat = FileNameFormat(separator: .underscore, lowercase: true)
        model.applyFileName()
        #expect(model.scan.name == "lumen_invoice")
        #expect(model.scan.title == "Lumen invoice")
    }

    @Test func buildsThePDFWithItsSize() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 2)
        await model.buildPDF(delay: .zero)
        guard case .ready(let url, let size) = model.pdf else {
            Issue.record("PDF not ready: \(model.pdf)")
            return
        }
        #expect(url == fixture.store.pdfURL(of: model.scan))
        #expect(size > 1000)
    }

    @Test func qualityOverrideIsDroppedWhenItMatchesTheDefault() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.setQuality(.small)
        #expect(model.scan.quality == .small)
        #expect(model.quality == .small)
        model.setQuality(fixture.settings.value.quality)
        #expect(model.scan.quality == nil)
    }
}
