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
    let now: @Sendable () -> Date
    @ObservationIgnored private var models: [UUID: ScanModel] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// The last reading of the Paperless correspondents and document types, as the app became active or an owner was connected.
    @ObservationIgnored public private(set) var readingPaperless: Task<Void, Never>?
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
        settings.didChangeFileNameFormat = { [weak self] in self?.applyFileNameFormat(of: $0) }
        archiver?.didConnect = { [weak self] id in
            self?.readingPaperless = Task { [weak self] in await self?.readPaperless(of: [id]) }
        }
    }

    /// A new file name format renames the scans of its owner not sent yet, and the one in Review; a scan on its way to Paperless keeps the name its upload reads the PDF by.
    private func applyFileNameFormat(of owners: Set<UUID>) {
        for scan in scans {
            guard let owner = scan.owner?.id, owners.contains(owner), scan.sent == nil || path.last == scan.id, scan.archiving?.isInProgress != true else { continue }
            model(for: scan.id)?.applyFileName()
        }
    }

    public var store: ScanStore { processor.store }

    /// Page work and PDFs wait while the app is not active, as the GPU cannot be used in the background; when it is active again, they go on, the PDFs that could not be made are asked for again, the list is refreshed and the results of uploads are applied.
    /// Settings changed meanwhile are saved before the app can be stopped.
    public func setActive(_ isActive: Bool) {
        processor.gate.isPaused = !isActive
        if isActive {
            for model in models.values { model.retryFailedPDF() }
            refresh()
            readingPaperless = Task { [weak self] in await self?.readPaperless(unlessReadWithin: Self.paperlessObjectsLifetime) }
        } else {
            settings.save()
        }
        archiver?.isActive = isActive
    }

    /// How long the Paperless correspondents and document types read stay current when the app becomes active again.
    public static let paperlessObjectsLifetime: TimeInterval = 10 * 60

    /// Reads the correspondents and document types of the Paperless servers of the connected owners, or of some of them, unless read within `maximumAge`;
    /// the scans not sent of the owners read get their issuer and document type named like the server's.
    public func readPaperless(of ownerIDs: Set<UUID>? = nil, unlessReadWithin maximumAge: TimeInterval? = 0) async {
        guard let archiver else { return }
        let owners = settings.value.owners.filter { ownerIDs?.contains($0.id) ?? true }
        let read = await archiver.readCatalogs(of: owners, unlessReadWithin: maximumAge)
        guard !read.isEmpty else { return }
        for scan in scans where scan.sent == nil && scan.archiving?.isInProgress != true && read.contains(settings.value.owner(scan.owner?.id).id) {
            guard let model = model(for: scan.id), model.nameLikePaperless() else { continue }
            model.applyFileName()
        }
    }

    /// The correspondents or document types of the owner's Paperless server, once read; nil when the owner is not connected.
    func paperlessObjects(_ kind: PaperlessObjectKind, of owner: Owner) -> PaperlessMatcher? {
        isConnected(owner) ? archiver?.catalogs.matcher(kind, of: owner) : nil
    }

    /// How long a scan stays on this iPhone once it was archived or shared.
    public static let sentScanLifetime: TimeInterval = 24 * 60 * 60

    /// Deletes the folders of scans never saved and the scans sent longer ago than `sentScanLifetime`, except the one open in Review or in the camera, then reloads the list.
    /// A scan never sent is never deleted: it is the only copy of the document; nor is one on its way to Paperless, whatever sent it before.
    public func refresh() {
        reload()
        store.deleteUnsavedScans(keeping: Set(models.keys))
        let cutoff = now().addingTimeInterval(-Self.sentScanLifetime)
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

    /// Opens a scan from Home in Review.
    public func open(_ id: UUID) {
        guard scans.contains(where: { $0.id == id }) else { return }
        path = [id]
    }

    /// Closing the camera on pages, even ones still being made, is the same as Done; a new scan without any is dropped.
    public func closeCamera() {
        guard let camera else { return }
        if camera.isEmpty {
            models[camera.id] = nil
            self.camera = nil
        } else {
            finishCapture(camera)
        }
    }

    public func finishCapture(_ model: ScanModel) {
        model.finishCapture()
        camera = nil
        if path.last != model.id { path = [model.id] }
    }

    /// The scans not sent yet nor on their way to Paperless, which Home offers to send at once.
    public var notSent: [Scan] {
        scans.filter { $0.sent == nil && $0.archiving?.isInProgress != true }
    }

    /// Confirms the scans that went out; Paperless confirms its own once the server took them.
    public func didSend(_ models: [ScanModel], by method: SendMethod) {
        guard !models.isEmpty else { return }
        for model in models { model.markSent(method) }
        path = []
        showToast(models.count == 1 ? method.pastTense : "\(models.count) scans \(method.pastTense.lowercased())")
    }

    /// The owners of the scans, each once, in the order of the scans.
    static func owners(of models: [ScanModel]) -> [Owner] {
        models.reduce(into: []) { owners, model in
            if !owners.contains(where: { $0.id == model.owner.id }) { owners.append(model.owner) }
        }
    }

    /// Whether Archive sends the scan in a single tap: its owner has a Paperless server.
    public func archives(_ model: ScanModel) -> Bool {
        isConnected(model.owner)
    }

    /// The owner of the scan when it has no Paperless server, for the send bar to offer to connect it.
    public func ownerToConnect(for model: ScanModel) -> Owner? {
        archiver == nil || archives(model) ? nil : model.owner
    }

    /// Whether the owner's documents go out to its Paperless server in a single tap.
    public func isConnected(_ owner: Owner) -> Bool {
        archiver?.isConnected(owner) == true
    }

    /// Whether an owner's documents go out to its Paperless server.
    public var hasConnectedOwner: Bool {
        settings.value.owners.contains(where: isConnected)
    }

    /// The host of the owner's Paperless server once it is connected.
    public func archivesTo(_ owner: Owner) -> String? {
        isConnected(owner) ? owner.paperlessHost : nil
    }

    /// Archive, named, then Share when the owner of the scan has a Paperless server, even once archived, as the document may have been deleted from Paperless; Share alone otherwise.
    public func sendButtons(for model: ScanModel) -> SendButtons {
        guard archives(model) else {
            return SendButtons(named: .share, title: SendMethod.share.title, isProminent: false)
        }
        return SendButtons(named: .paperless, title: model.scan.archiveTitle, isProminent: true, round: .share)
    }

    /// The swipe actions of a scan on Home, in order: Archive when its owner has a Paperless server, even once sent, or Try Again once its upload failed, then Share.
    /// None while it is on its way to Paperless.
    public func swipeActions(for scan: Scan) -> [RowAction] {
        guard scan.archiving?.isInProgress != true else { return [] }
        let connected = isConnected(settings.value.owner(scan.owner?.id))
        if scan.archiving != nil { return connected ? [.tryAgain, .share] : [.share] }
        return connected ? [.archive, .share] : [.share]
    }

    /// Offered once more than one scan was not sent: to Paperless when every owner of the scans has a server, to the share sheet otherwise.
    public var notSentOffer: NotSentOffer? {
        let scans = notSent
        guard scans.count > 1 else { return nil }
        return NotSentOffer(scans: scans, archives: scans.allSatisfy { isConnected(settings.value.owner($0.owner?.id)) })
    }

    /// Starts sending each scan to the Paperless server of its owner; Home tells when they are archived.
    public func archive(_ models: [ScanModel]) async throws {
        guard let archiver, !models.isEmpty else { return }
        try archiver.check(models)
        path = []
        showToast(models.count == 1 ? "Archiving to Paperless" : "Archiving \(models.count) scans to Paperless")
        await archiver.archive(models)
    }

    /// Under the send buttons, before the pages and size, with several owners: the owner of the scan.
    public func ownerLabel(of model: ScanModel) -> String? {
        settings.value.hasSeveralOwners ? model.owner.name : nil
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

    /// A model let go without a page, as when the camera closes, is handed out again once it saves its scan, as when the photo being taken comes in.
    private func makeModel(_ scan: Scan) -> ScanModel {
        let model = ScanModel(scan: scan, processor: processor, settings: settings, now: now)
        model.didSave = { [weak self, weak model] scan in
            guard let self else { return }
            if models[scan.id] == nil { models[scan.id] = model }
            list(scan)
        }
        model.didDeleteStoredScan = { [weak self] id in self?.scans.removeAll { $0.id == id } }
        model.didStopArchiving = { [weak self] id in self?.archiver?.cancel(id) }
        model.otherScans = { [weak self] in self?.scans ?? [] }
        model.paperless = { [weak self] owner, kind in self?.paperlessObjects(kind, of: owner) }
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

/// The buttons of the send bar before Delete: the one shown with its name, then the other way as a round button.
public struct SendButtons: Equatable {
    public var named: SendMethod
    /// "Archive", "Try Again", "Try Now", "Share".
    public var title: String
    /// Filled with the accent color, as it sends in a single tap; Share only opens the share sheet.
    public var isProminent: Bool
    public var round: SendMethod?
}

/// A swipe action of a scan on Home.
public enum RowAction: Equatable, Sendable {
    /// Archive again after a failed upload.
    case archive, tryAgain, share

    public var method: SendMethod {
        self == .share ? .share : .paperless
    }
}

/// The card on Home that sends every scan not sent in one tap.
public struct NotSentOffer: Equatable {
    public var scans: [Scan]
    /// To Paperless, as every owner of the scans has a server; to the share sheet otherwise.
    public var archives: Bool
}
