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
    @ObservationIgnored private var models: [UUID: ScanModel] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    public init(processor: ScanProcessor, settings: SettingsStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.processor = processor
        self.settings = settings
        self.now = now
        refresh()
        for scan in scans where !scan.pending.isEmpty { _ = model(for: scan.id) }
    }

    public var store: ScanStore { processor.store }

    /// Page work and PDFs wait while the app is not active, as the GPU cannot be used in the background; when it is active again, they go on and the list is refreshed.
    /// Settings changed meanwhile are saved before the app can be stopped.
    public func setActive(_ isActive: Bool) {
        processor.gate.isPaused = !isActive
        if isActive { refresh() } else { settings.save() }
    }

    /// Deletes expired scans, except the one open in Review or in the camera, and unreadable scan folders, then reloads the list.
    public func refresh() {
        reload()
        guard let days = settings.value.keepScans.days else { return }
        store.deleteUnreadableScans(keeping: Set(models.keys))
        let cutoff = now().addingTimeInterval(-Double(days) * 86400)
        delete(Set(scans.filter { $0.created < cutoff && camera?.id != $0.id && path.last != $0.id }.map(\.id)))
    }

    private func reload() {
        scans = store.all()
    }

    /// Puts a saved scan in the list, newest first.
    private func list(_ scan: Scan) {
        if let index = scans.firstIndex(where: { $0.id == scan.id }) {
            if scans[index] != scan { scans[index] = scan }
        } else {
            scans.insert(scan, at: scans.firstIndex { $0.created < scan.created } ?? scans.endIndex)
        }
    }

    public func model(for id: UUID) -> ScanModel? {
        models[id] ?? scans.first { $0.id == id }.map(makeModel)
    }

    @discardableResult
    public func startScan() -> ScanModel {
        let created = now()
        let model = makeModel(Scan(created: created, name: "", title: FileNamer.fallback(for: created)))
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
        let done = models.count == 1 ? method.pastTense : "\(models.count) scans \(method.pastTense.lowercased())"
        let owners = Self.owners(of: models)
        let owner = owners.count == 1 ? owners[0] : nil
        switch method {
        case .email where owner?.hasValidEmail == true: showToast("\(done) to \(owner!.email)")
        case .files: showToast("\(done) to \(owner?.archiveFolder?.name ?? "Files")")
        default: showToast(done)
        }
    }

    /// The owners of the scans, each once, in the order of the scans.
    static func owners(of models: [ScanModel]) -> [Owner] {
        models.reduce(into: []) { owners, model in
            if !owners.contains(where: { $0.id == model.owner.id }) { owners.append(model.owner) }
        }
    }

    /// The scans grouped by owner, in the order of the scans, to send each group where its owner's go.
    public func byOwner(_ models: [ScanModel]) -> [(owner: Owner, scans: [ScanModel])] {
        Self.owners(of: models).map { owner in (owner, models.filter { $0.owner.id == owner.id }) }
    }

    /// The first owner of these scans without a folder to save them to.
    public func ownerWithoutFolder(among models: [ScanModel]) -> Owner? {
        Self.owners(of: models).first { $0.archiveFolder == nil }
    }

    /// A PDF could not be saved; `saved` lists the scans saved before it.
    public struct ArchiveError: Error {
        public let saved: [UUID]
    }

    /// Copies each PDF to the folder of its owner, in order, up to the first that cannot be saved, and confirms the ones saved like any other sending.
    /// The copies run off the main actor, as a folder in iCloud Drive or another provider can take long to reach.
    public func saveToArchive(_ models: [ScanModel]) async throws {
        var saved: [ScanModel] = []
        defer { didSend(saved, by: .files) }
        for model in models {
            let owner = model.owner
            guard let folder = owner.archiveFolder, case .ready(let url, _) = model.pdf else { throw ArchiveError(saved: saved.map(\.id)) }
            let name = model.scan.name, separator = owner.fileNameFormat.separator.character
            let refreshed: ArchiveFolder
            do {
                refreshed = try await Task.detached(priority: .userInitiated) {
                    var folder = folder
                    try folder.save(url, as: name, separator: separator)
                    return folder
                }.value
            } catch {
                throw ArchiveError(saved: saved.map(\.id))
            }
            var current = settings.value.owner(owner.id)
            if refreshed != folder, current.archiveFolder == folder {
                current.archiveFolder = refreshed
                settings.value.updateOwner(current)
            }
            saved.append(model)
        }
    }

    /// Under the send buttons: where Email sends the scans, when there is something to say.
    public func destination(of models: [ScanModel]) -> String? {
        let groups = byOwner(models)
        guard !groups.isEmpty else { return nil }
        guard settings.value.hasSeveralOwners else {
            return groups.first.flatMap { $0.owner.hasValidEmail ? "To \($0.owner.email)" : nil }
        }
        guard groups.count == 1, let owner = groups.first?.owner else {
            return "\(groups.count) emails: " + groups.map { "\($0.owner.name) (\($0.scans.count))" }.joined(separator: ", ")
        }
        return owner.hasValidEmail ? "\(owner.name) · To \(owner.email)" : owner.name
    }

    /// The scans of an owner, which deleting it moves or deletes.
    public func scans(of ownerID: UUID) -> [Scan] {
        scans.filter { $0.owner?.id == ownerID }
    }

    /// Deletes an owner, never the default one; its scans go to another owner, or are deleted without one.
    public func deleteOwner(_ id: UUID, movingScansTo newOwner: UUID?) {
        guard id != settings.value.defaultOwnerID, settings.value.hasOwner(id) else { return }
        if let newOwner, newOwner == id || !settings.value.hasOwner(newOwner) { return }
        let owned = scans(of: id)
        if let newOwner {
            for scan in owned { model(for: scan.id)?.assignOwner(newOwner) }
        } else {
            delete(Set(owned.map(\.id)))
        }
        settings.removeOwner(id, movingTo: newOwner)
    }

    public func delete(_ id: UUID) {
        delete([id])
    }

    /// Deletes the scans, then updates the list once.
    public func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            if let model = models.removeValue(forKey: id) {
                model.delete()
            } else if let scan = scans.first(where: { $0.id == id }) {
                store.delete(scan)
            }
        }
        scans.removeAll { ids.contains($0.id) }
        path.removeAll(where: ids.contains)
        if let camera, ids.contains(camera.id) { self.camera = nil }
    }

    /// Deletes every scan and its PDF from this device; what was sent or saved elsewhere stays.
    public func deleteAllScans() {
        reload()
        delete(Set(scans.map(\.id)))
        store.deleteUnreadableScans(keeping: Set(models.keys))
    }

    private func makeModel(_ scan: Scan) -> ScanModel {
        let model = ScanModel(scan: scan, processor: processor, settings: settings, now: now)
        model.didSave = { [weak self] in self?.list($0) }
        model.didDeleteStoredScan = { [weak self] id in self?.scans.removeAll { $0.id == id } }
        model.otherScans = { [weak self] in self?.scans ?? [] }
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
