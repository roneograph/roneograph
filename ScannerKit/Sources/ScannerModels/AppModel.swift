import Foundation
import Observation
import ScannerKit

@MainActor @Observable
public final class AppModel {
    /// Scans pushed on Home; only ever one, the scan under review.
    public var path: [UUID] = []
    /// The scan the camera adds pages to, nil when the camera is closed.
    public var camera: ScanModel?
    public var showingSettings = false
    public private(set) var scans: [Scan] = []
    public private(set) var toast: String?
    public let settings: SettingsStore
    private let processor: ScanProcessor
    private let now: @Sendable () -> Date
    private var models: [UUID: ScanModel] = [:]
    private var toastTask: Task<Void, Never>?

    public init(processor: ScanProcessor, settings: SettingsStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.processor = processor
        self.settings = settings
        self.now = now
        refresh()
    }

    public var store: ScanStore { processor.store }

    /// Deletes expired scans and reloads the list.
    public func refresh() {
        if let days = settings.value.keepScans.days {
            store.deleteScans(olderThan: now().addingTimeInterval(-Double(days) * 86400))
        }
        reload()
    }

    func reload() {
        scans = store.all()
    }

    public func model(for id: UUID) -> ScanModel? {
        if let model = models[id] { return model }
        return (scans.first { $0.id == id } ?? store.all().first { $0.id == id }).map(makeModel)
    }

    @discardableResult
    public func startScan() -> ScanModel {
        let created = now()
        let model = makeModel(Scan(created: created, name: "", title: FileNamer().fallback(for: created)))
        model.applyFileName()
        camera = model
        return model
    }

    public func continueScan(_ id: UUID) {
        camera = model(for: id)
    }

    /// The pages stay: an unfinished scan shows as in progress on Home.
    public func closeCamera() {
        if let camera, camera.scan.pages.isEmpty, camera.processing == 0 {
            models[camera.id] = nil
        }
        camera = nil
        reload()
    }

    public func finishCapture(_ model: ScanModel) {
        model.finishCapture()
        camera = nil
        if path.last != model.id { path = [model.id] }
    }

    /// The finished scans not sent yet, which Home offers to select at once.
    public var notSent: [Scan] {
        scans.filter { $0.isFinished && $0.sent == nil }
    }

    public func didSend(_ models: [ScanModel], by method: SendMethod) {
        guard !models.isEmpty else { return }
        for model in models { model.markSent(method) }
        path = []
        let settings = settings.value
        let done = models.count == 1 ? method.pastTense : "\(models.count) scans \(method.pastTense.lowercased())"
        switch method {
        case .email where settings.hasValidEmail: showToast("\(done) to \(settings.email)")
        case .files: showToast("\(done) to \(settings.archiveFolder?.name ?? "Files")")
        default: showToast(done)
        }
    }

    /// Stops at the first PDF that cannot be saved; the ones saved before it are confirmed.
    public struct ArchiveError: Error {
        public let saved: [UUID]
    }

    /// Copies each PDF to the archive folder, in order, then confirms them like any other sending.
    public func saveToArchive(_ models: [ScanModel]) throws {
        var saved: [ScanModel] = []
        defer { didSend(saved, by: .files) }
        for model in models {
            guard var folder = settings.value.archiveFolder, case .ready(let url, _) = model.pdf else { throw ArchiveError(saved: saved.map(\.id)) }
            do {
                try folder.save(url, as: model.scan.name, separator: settings.value.fileNameFormat.separator.character)
            } catch {
                throw ArchiveError(saved: saved.map(\.id))
            }
            if folder != settings.value.archiveFolder { settings.value.archiveFolder = folder }
            saved.append(model)
        }
    }

    public func delete(_ id: UUID) {
        if let model = models.removeValue(forKey: id) {
            model.delete()
        } else if let scan = scans.first(where: { $0.id == id }) {
            store.delete(scan)
        }
        path.removeAll { $0 == id }
        if camera?.id == id { camera = nil }
        reload()
    }

    /// Deletes every scan and its PDF from this device; what was sent or saved elsewhere stays.
    public func deleteAllScans() {
        reload()
        for scan in scans { delete(scan.id) }
    }

    private func makeModel(_ scan: Scan) -> ScanModel {
        let model = ScanModel(scan: scan, processor: processor, settings: settings, now: now)
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
