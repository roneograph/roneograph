import Foundation
import Observation
import ScannerKit

@MainActor @Observable
final class AppModel {
    /// Scans pushed on Home; only ever one, the scan under review.
    var path: [UUID] = []
    /// The scan the camera adds pages to, nil when the camera is closed.
    var camera: ScanModel?
    var showingSettings = false
    private(set) var scans: [Scan] = []
    private(set) var toast: String?
    let settings: SettingsStore
    private let processor: ScanProcessor
    private var models: [UUID: ScanModel] = [:]
    private var toastTask: Task<Void, Never>?

    init(processor: ScanProcessor, settings: SettingsStore) {
        self.processor = processor
        self.settings = settings
        refresh()
    }

    var store: ScanStore { processor.store }

    /// Deletes expired scans and reloads the list.
    func refresh() {
        store.deleteScans(olderThan: Date(timeIntervalSinceNow: -Double(settings.value.keepDays) * 86400))
        reload()
    }

    func reload() {
        scans = store.all()
    }

    func model(for id: UUID) -> ScanModel? {
        if let model = models[id] { return model }
        return (scans.first { $0.id == id } ?? store.all().first { $0.id == id }).map(makeModel)
    }

    @discardableResult
    func startScan() -> ScanModel {
        let model = makeModel(Scan(name: "", title: FileNamer().fallback(for: .now)))
        model.applyFileName()
        camera = model
        return model
    }

    func continueScan(_ id: UUID) {
        camera = model(for: id)
    }

    /// The pages stay: an unfinished scan shows as in progress on Home.
    func closeCamera() {
        if let camera, camera.scan.pages.isEmpty, camera.processing == 0 {
            models[camera.id] = nil
        }
        camera = nil
        reload()
    }

    func finishCapture(_ model: ScanModel) {
        model.finishCapture()
        camera = nil
        if path.last != model.id { path = [model.id] }
    }

    func didSend(_ model: ScanModel, by method: SendMethod) {
        model.markSent(method)
        path = []
        let email = settings.value
        showToast(method == .email ? (email.hasValidEmail ? "Emailed to \(email.email)" : "Emailed") : "Shared")
    }

    func delete(_ id: UUID) {
        if let model = models.removeValue(forKey: id) {
            model.delete()
        } else if let scan = scans.first(where: { $0.id == id }) {
            store.delete(scan)
        }
        path.removeAll { $0 == id }
        reload()
    }

    private func makeModel(_ scan: Scan) -> ScanModel {
        let model = ScanModel(scan: scan, processor: processor, settings: settings)
        model.didSave = { [weak self] in self?.reload() }
        models[scan.id] = model
        return model
    }

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}
