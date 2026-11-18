import CoreImage
import Foundation
@testable import ScannerKit
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
    let suite = "ScannerModelsTests-\(UUID().uuidString)"
    /// Keeps the models alive, as the app model does.
    private var models: [ScanModel] = []

    init(background: (any BackgroundActivity)? = nil) throws {
        store = ScanStore(scansDirectory: root.appending(path: "Application Support/Scans"), documentsDirectory: root.appending(path: "Documents"))
        try FileManager.default.createDirectory(at: store.documentsDirectory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)!
        settings = SettingsStore(defaults: defaults, appFolder: store.documentsDirectory)
        processor = ScanProcessor(store: store, paper: .a4, background: background)
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

    /// Holds the processing gate, so the page work of every scan waits, until the returned closure is called.
    func holdGate() async -> () async -> Void {
        let (entered, didEnter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        let gate = processor.gate
        let holder = Task {
            await gate.run {
                didEnter.finish()
                for await _ in released {}
            }
        }
        for await _ in entered {}
        return {
            release.finish()
            await holder.value
        }
    }

    /// Waits until that much work waits for the processing gate.
    func waitUntilGateHasWaiting(_ count: Int) async throws {
        while processor.gate.waitingCount < count { try await Task.sleep(for: .milliseconds(1)) }
    }

    func pdfExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: store.documentsDirectory.appending(path: "\(name).pdf").path(percentEncoded: false))
    }
}
