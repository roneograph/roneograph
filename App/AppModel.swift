import Foundation
import Observation
import ScannerKit

@MainActor @Observable
final class AppModel {
    enum Screen {
        case camera, review
    }

    var screen = Screen.camera
    private(set) var scan: ScanModel
    let settings: SettingsStore
    private let processor: ScanProcessor

    init(processor: ScanProcessor, settings: SettingsStore) {
        self.processor = processor
        self.settings = settings
        processor.store.deleteScans(olderThan: Date(timeIntervalSinceNow: -Double(settings.value.keepDays) * 86400))
        let unfinished = processor.store.all().first { !$0.isFinished && !$0.pages.isEmpty }
        scan = ScanModel(scan: unfinished ?? Scan(name: "", title: FileNamer().fallback(for: .now)), processor: processor, settings: settings)
        if unfinished == nil { scan.applyFileName() }
    }

    func finishCapture() {
        scan.finishCapture()
        screen = .review
    }

    func addPages() {
        screen = .camera
    }

    func newScan() {
        scan = ScanModel(scan: Scan(name: "", title: FileNamer().fallback(for: .now)), processor: processor, settings: settings)
        scan.applyFileName()
        screen = .camera
    }

    func deleteScan() {
        scan.delete()
        newScan()
    }
}
