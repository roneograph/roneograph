import CoreImage
import Foundation
import ScannerKit
import ScannerKitTesting
@testable import ScannerModels

/// A temporary scan store, settings and processor, removed after each test.
@MainActor
final class Fixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "ScannerModelsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let store: ScanStore
    let settings: SettingsStore
    let processor: ScanProcessor
    let defaults: UserDefaults
    private let suite = "ScannerModelsTests-\(UUID().uuidString)"
    /// Keeps the models alive, as the app model does.
    private var models: [ScanModel] = []

    init() throws {
        store = ScanStore(scansDirectory: root.appending(path: "Application Support/Scans"), documentsDirectory: root.appending(path: "Documents"))
        try FileManager.default.createDirectory(at: store.documentsDirectory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)!
        settings = SettingsStore(defaults: defaults)
        processor = ScanProcessor(store: store, context: CIContext(), paper: .a4)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func scanModel(title: String = "Scan 2026-11-15") -> ScanModel {
        let model = ScanModel(scan: Scan(name: "", title: title), processor: processor, settings: settings)
        model.applyFileName()
        models.append(model)
        return model
    }

    /// A scan with pages already processed.
    func scanModel(pages: Int) async -> ScanModel {
        let model = scanModel()
        for _ in 0..<pages { model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil) }
        await model.waitUntilIdle()
        return model
    }

    /// A one-page scan captured from Home, the camera closed with Done.
    func capturedScan(in app: AppModel) async -> ScanModel {
        let scan = app.startScan()
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await scan.waitUntilIdle()
        app.finishCapture(scan)
        return scan
    }

    func pdfExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: store.documentsDirectory.appending(path: "\(name).pdf").path(percentEncoded: false))
    }
}
