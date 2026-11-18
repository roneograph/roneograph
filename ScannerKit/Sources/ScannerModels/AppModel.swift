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
    /// Nil when Paperless cannot be used, as in most tests.
    public let archiver: Archiver?
    private let processor: ScanProcessor
    private let now: @Sendable () -> Date
    @ObservationIgnored private var models: [UUID: ScanModel] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// Replaced in tests, to fail saving to the folder.
    @ObservationIgnored var saveToFolder: @Sendable (ArchiveFolder, URL, String, String) throws -> ArchiveFolder = { folder, file, name, separator in
        var folder = folder
        try folder.save(file, as: name, separator: separator)
        return folder
    }

    public init(processor: ScanProcessor, settings: SettingsStore, archiver: Archiver? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.processor = processor
        self.settings = settings
        self.archiver = archiver
        self.now = now
        archiver?.model = { [weak self] in self?.model(for: $0) }
        archiver?.scans = { [weak self] in self?.scans ?? [] }
        if !settings.hasUnreadableSettings { archiver?.forgetTokens(keeping: settings.value.owners) }
        refresh()
        for scan in scans where !scan.pending.isEmpty { _ = model(for: scan.id) }
    }

    public var store: ScanStore { processor.store }

    /// Page work and PDFs wait while the app is not active, as the GPU cannot be used in the background; when it is active again, they go on, the list is refreshed and the results of uploads are applied.
    /// Settings changed meanwhile are saved before the app can be stopped.
    public func setActive(_ isActive: Bool) {
        processor.gate.isPaused = !isActive
        if isActive { refresh() } else { settings.save() }
        archiver?.isActive = isActive
    }

    /// Deletes the scans sent longer ago than the retention, except the one open in Review or in the camera, and the folders of scans never saved, then reloads the list.
    /// A scan never sent is never deleted: it is the only copy of the document; nor is one on its way to Paperless, whatever sent it before.
    public func refresh() {
        reload()
        guard let days = settings.value.keepScans.days else { return }
        store.deleteUnsavedScans(keeping: Set(models.keys))
        let cutoff = now().addingTimeInterval(-Double(days) * 86400)
        delete(Set(scans.filter { scan in
            guard let sent = scan.sent, scan.archiving?.isInProgress != true else { return false }
            return sent.date < cutoff && camera?.id != scan.id && path.last != scan.id
        }.map(\.id)))
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

    /// Opens a scan from Home: Review once it is finished, the camera to add pages while it is in progress, which has nothing to send yet.
    public func open(_ id: UUID) {
        guard let scan = scans.first(where: { $0.id == id }) else { return }
        if scan.isFinished { path = [id] } else { continueScan(id) }
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

    /// The finished scans not sent yet nor on their way to Paperless, which Home offers to select at once.
    public var notSent: [Scan] {
        scans.filter { $0.isFinished && $0.sent == nil && $0.archiving?.isInProgress != true }
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

    /// The owners the send bar is for: those of the scans, every owner when no scan is selected yet.
    public func sendingOwners(for models: [ScanModel]) -> [Owner] {
        models.isEmpty ? settings.value.owners : Self.owners(of: models)
    }

    /// The send buttons for these scans, in the order of the bar, each when every owner of the scans has it: Archive and Email once it has a server or an address, Save to Files and Share unless turned off.
    public func sendMethods(for models: [ScanModel]) -> [SendMethod] {
        let owners = sendingOwners(for: models)
        var methods: [SendMethod] = []
        if let archiver, owners.allSatisfy(archiver.isConnected) { methods.append(.paperless) }
        if owners.allSatisfy(\.hasValidEmail) { methods.append(.email) }
        if owners.allSatisfy(\.showsSaveToFiles) { methods.append(.files) }
        if owners.allSatisfy(\.showsShare) { methods.append(.share) }
        return methods
    }

    /// The send button shown with its name: the first in the order of the bar that sends in a single tap for every owner of the scans, never Share, which only opens the share sheet.
    public func namedSendMethod(for models: [ScanModel]) -> SendMethod? {
        let owners = sendingOwners(for: models)
        return sendMethods(for: models).first { method in
            method != .share && owners.allSatisfy { isSet(method, for: $0) }
        }
    }

    /// Whether the owner's documents go out this way in a single tap: a connected Paperless server, a valid address, Save to Files shown with a folder chosen, Share shown.
    public func isSet(_ method: SendMethod, for owner: Owner) -> Bool {
        switch method {
        case .paperless: archiver?.isConnected(owner) == true
        case .email: owner.hasValidEmail
        case .files: owner.showsSaveToFiles && owner.archiveFolder != nil
        case .share: owner.showsShare
        }
    }

    /// Whether every owner of these scans has a folder, so Save to Files needs a single tap.
    public func hasFolder(for models: [ScanModel]) -> Bool {
        !models.isEmpty && ownerWithoutFolder(among: models) == nil
    }

    /// Home offers to set up sending until an owner has an address or a Paperless server, or the card is closed.
    public var suggestsSendSetup: Bool {
        !settings.value.dismissedSendSetup && !settings.value.owners.contains { $0.hasValidEmail || $0.paperless != nil }
    }

    /// Starts sending each scan to the Paperless server of its owner; Home tells when they are archived.
    public func archive(_ models: [ScanModel]) async throws {
        guard let archiver, !models.isEmpty else { return }
        try archiver.check(models)
        path = []
        showToast(models.count == 1 ? "Archiving to Paperless" : "Archiving \(models.count) scans to Paperless")
        await archiver.archive(models)
    }

    /// A PDF could not be saved; `saved` lists the scans saved before it.
    public struct ArchiveError: Error {
        public let saved: [UUID]
        public var isStorageFull = false
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
                let saveToFolder = saveToFolder
                refreshed = try await Task.detached(priority: .userInitiated) {
                    try saveToFolder(folder, url, name, separator)
                }.value
            } catch {
                throw ArchiveError(saved: saved.map(\.id), isStorageFull: error.isStorageFull)
            }
            var current = settings.value.owner(owner.id)
            if refreshed != folder, current.archiveFolder == folder {
                current.archiveFolder = refreshed
                settings.value.updateOwner(current)
            }
            saved.append(model)
        }
    }

    /// Under the send buttons, before the pages and size, with several owners: the owner of the scans, or how many there are.
    public func ownerLabel(of models: [ScanModel]) -> String? {
        guard settings.value.hasSeveralOwners else { return nil }
        let owners = Self.owners(of: models)
        return switch owners.count {
        case 0: nil
        case 1: owners[0].name
        default: owners.count.counted("owner")
        }
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
        try? archiver?.setToken(nil, for: id)
        settings.removeOwner(id, movingTo: newOwner)
    }

    public func delete(_ id: UUID) {
        delete([id])
    }

    /// Deletes the scans, then updates the list once.
    public func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for scan in scans where ids.contains(scan.id) && scan.archiving?.isInProgress == true {
            archiver?.cancel(scan.id)
        }
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
        store.deleteAllScanFolders(keeping: Set(models.keys))
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
