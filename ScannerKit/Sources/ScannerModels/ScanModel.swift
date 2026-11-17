import Foundation
import Observation
import ScannerKit

/// One scan while it is captured, reviewed and sent; every change is saved right away.
@MainActor @Observable
public final class ScanModel: Identifiable {
    public enum PDFState: Equatable {
        case idle, building, failed
        case ready(url: URL, size: Int)
    }

    /// What the PDF depends on; a change triggers a new PDF.
    public struct PDFInputs: Equatable {
        var name: String
        var title: String
        var pages: [ScanPage]
    }

    public let id: UUID
    public private(set) var scan: Scan
    /// Page edits not applied yet.
    public private(set) var updating = 0
    public private(set) var pdf = PDFState.idle
    /// What the ready PDF was made from, to tell whether it is still current.
    private var pdfMadeFrom: PDFInputs?
    /// The PDF being made; another build waits for it, so two never run at once.
    private var pdfBuild: Task<Void, Never>?
    /// Replaced in tests, to hold or count builds.
    var makePDFData: @concurrent @Sendable (Scan) async throws -> Data
    /// Replaced in tests, to fail reading the page.
    var readDocument: @concurrent @Sendable (ScanPage, UUID, Set<String>) async throws -> DetectedDocument?
    public private(set) var failure: String?
    private let processor: ScanProcessor
    private let settings: SettingsStore
    /// Called after every save, so the list of scans stays current.
    var didSave: (() -> Void)?
    private var queue: Task<Void, Never>?
    private var isDeleted = false
    private let now: @Sendable () -> Date

    public init(scan: Scan, processor: ScanProcessor, settings: SettingsStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.id = scan.id
        var scan = scan
        if scan.owner == nil { scan.owner = ScanOwner(id: settings.value.defaultOwnerID, isDefault: true) }
        self.scan = scan
        self.processor = processor
        self.settings = settings
        self.now = now
        makePDFData = { scan in try await processor.pdfData(of: scan) }
        readDocument = { page, scanID, ownLines in try await processor.detectDocument(on: page, scanID: scanID, ownLines: ownLines) }
        for page in scan.pending { process(page) }
    }

    private var store: ScanStore { processor.store }
    public var pdfInputs: PDFInputs { PDFInputs(name: scan.fileName, title: scan.title, pages: scan.pages) }
    public var fallbackTitle: String { FileNamer.fallback(for: scan.created) }
    /// The name a typed name becomes: trimmed, with single spaces, the first suggestion or the date when empty.
    public func finalName(_ name: String) -> String { FileNamer.finalName(name, fallback: scan.suggestions.first ?? fallbackTitle) }
    /// Pages captured but not processed yet.
    public var processing: Int { scan.pending.count }
    private var isEmpty: Bool { scan.pages.isEmpty && scan.pending.isEmpty }
    public var isBusy: Bool { processing > 0 || updating > 0 }
    /// The name remembered for the issuer, while it is the name of the scan.
    public var rememberedName: String? { scan.remembered.contains(.name) ? scan.title : nil }
    /// Where the PDF goes and how it is named.
    public var owner: Owner { settings.value.owner(scan.owner?.id) }
    /// True when nothing on the page told the owner and none was chosen: the scan got the default owner.
    public var hasDefaultOwner: Bool { scan.owner?.isDefault ?? true }
    /// Under Owner in Review: "Default" while the scan has the default owner because nothing told another one.
    public var ownerCaption: String? { hasDefaultOwner && owner.id == settings.value.defaultOwnerID ? "Default" : nil }
    public var fileNameFormat: FileNameFormat { owner.fileNameFormat }

    /// The file name a name and details get with the format of the owner, before avoiding collisions.
    /// A name the user typed is kept as typed; a suggested one leaves out what a custom format already shows.
    func fileName(for title: String) -> String {
        fileNameSegments(for: title).map(\.text).joined()
    }

    public func previewURL(of page: ScanPage) -> URL { store.previewURL(scanID: scan.id, pageID: page.id) }
    public func photoURL(of page: ScanPage) -> URL { store.photoURL(scanID: scan.id, pageID: page.id) }

    /// Waits until every captured page and every edit is done.
    public func waitUntilIdle() async {
        while let current = queue {
            await current.value
            if queue == current { return }
        }
    }

    /// Captures and edits run one at a time, in order, each starting from the result of the previous one.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            guard !isDeleted else { return }
            await work()
        }
    }

    /// Like `enqueue`, for work on page images, which also waits for the page work of other scans.
    private func enqueuePageWork(_ work: @escaping @MainActor () async -> Void) {
        let gate = processor.gate
        enqueue { [self] in
            await gate.run {
                guard !isDeleted else { return }
                await work()
            }
        }
    }

    // MARK: Capture

    /// Saves the photo and the scan right away, then makes the page.
    public func addPhoto(_ data: Data, liveQuad: Quad?) {
        let pending = PendingPage(liveQuad: liveQuad)
        do {
            try store.savePhoto(data, scanID: scan.id, pageID: pending.id)
        } catch {
            failure = "A page could not be processed."
            return
        }
        scan.pending.append(pending)
        save()
        process(pending)
    }

    /// A page that fails while the app is not active, where the GPU cannot be used, is made again once the app is active.
    private func process(_ pending: PendingPage) {
        let processor = processor, scanID = scan.id
        enqueuePageWork { [self] in
            do {
                let page = try await Task.detached(priority: .userInitiated) {
                    try await processor.addPage(pending, scanID: scanID)
                }.value
                guard !isDeleted else { return }
                scan.pending.removeAll { $0.id == pending.id }
                scan.pages.append(page)
                save()
                if scan.pages.count == 1 || scan.read == nil, let first = scan.pages.first { await suggestNames(from: first) }
            } catch {
                guard !isDeleted else { return }
                if processor.gate.isPaused {
                    process(pending)
                    return
                }
                scan.pending.removeAll { $0.id == pending.id }
                store.deletePageFiles(scanID: scanID, pageID: pending.id)
                if isEmpty {
                    store.delete(scan)
                    didSave?()
                } else {
                    save()
                }
                failure = "A page could not be processed."
            }
        }
    }

    public func finishCapture() {
        scan.isFinished = true
        save()
    }

    /// Reads the details and names on the first page; what the user corrected for the same issuer before wins over what was read.
    /// When the page cannot be read, it is read again after the next page.
    private func suggestNames(from page: ScanPage) async {
        let readDocument = readDocument, scanID = scan.id, date = scan.created, ownLines = settings.ownLines
        guard var document = try? await readDocument(page, scanID, ownLines), !isDeleted else { return }
        settings.recordHeaderLines(document.headerLines, issuerEvidence: document.issuerEvidence)
        scan.read = ReadDocument(details: document.details, parts: document.parts)
        scan.headerLines = document.headerLines
        let learned = settings.learnedIssuer(for: document.issuerKeys)
        var remembered = Set<RememberedValue>()
        if let issuer = learned?.issuer {
            if issuer != document.details.issuer { remembered.insert(.issuer) }
            document.details.issuer = issuer
            document.parts.issuer = issuer
        }
        if let category = learned?.category {
            if category != document.details.category { remembered.insert(.category) }
            document.details.category = category
        }
        let names = FileNamer.names(for: document.parts, date: date)
        scan.suggestions = names
        scan.suggestedParts = document.parts
        scan.issuerKeys = document.issuerKeys
        if scan.areDetailsEditedByUser {
            remembered = []
        } else {
            scan.details = document.details
        }
        if !scan.isNamedByUser, let first = names.first {
            let learnedName = learned?.name.map { FileNamer.finalName($0.name(details: document.details, date: document.details.date ?? date), fallback: first) }
            scan.title = learnedName ?? first
            if let learnedName, learnedName != first { remembered.insert(.name) }
        }
        if hasDefaultOwner {
            if let owner = settings.owner(recognizing: document.headerLines) {
                scan.owner = ScanOwner(id: owner)
            } else if let owner = learned?.owner, settings.value.hasSeveralOwners, settings.value.hasOwner(owner) {
                scan.owner = ScanOwner(id: owner)
                remembered.insert(.owner)
            }
        } else if scan.remembered.contains(.owner) {
            remembered.insert(.owner)
        }
        scan.remembered = remembered
        applyFileName()
    }

    // MARK: Pages

    /// The files of the page go once the work queued before is done, so an edit in progress does not write them again.
    /// Without pages left, the stored scan goes too, unless a page still being processed comes in.
    public func deletePage(_ id: UUID) {
        scan.pages.removeAll { $0.id == id }
        guard isEmpty || save() else { return }
        enqueue { [self] in
            if isEmpty {
                store.delete(scan)
                didSave?()
            } else {
                store.deletePageFiles(scanID: scan.id, pageID: id)
            }
        }
    }

    /// Moves a page to the place of another one, as when dropping it there.
    public func movePage(_ id: UUID, to target: UUID) {
        guard let from = scan.pages.firstIndex(where: { $0.id == id }), let to = scan.pages.firstIndex(where: { $0.id == target }), from != to else { return }
        scan.pages.insert(scan.pages.remove(at: from), at: to)
        save()
    }

    public func rotatePage(_ id: UUID) {
        editPage(id) { $0.rotate() }
    }

    public func setLook(_ look: PageLook?, of ids: [UUID]) {
        for id in ids {
            editPage(id) { $0.cleanup.look = look }
        }
    }

    /// Flattens the page again from its original photo, with a new outline or the whole photo.
    public func recrop(_ id: UUID, quad: Quad?) {
        update(id) { page, processor, scanID in
            try await processor.recrop(page, scanID: scanID, quad: quad)
        }
    }

    /// Changes how the page is rendered, then redraws its preview.
    private func editPage(_ id: UUID, _ edit: @escaping @Sendable (inout ScanPage) -> Void) {
        update(id) { page, processor, scanID in
            var page = page
            edit(&page)
            try processor.writePreview(of: page, scanID: scanID)
            return page
        }
    }

    /// Applies the change, off the main thread, to the page as it is when its turn comes, then publishes it with a new revision so its image reloads.
    private func update(_ id: UUID, _ change: @escaping @Sendable (ScanPage, ScanProcessor, UUID) async throws -> ScanPage) {
        updating += 1
        let processor = processor, scanID = scan.id
        enqueuePageWork { [self] in
            defer { updating -= 1 }
            guard let page = scan.pages.first(where: { $0.id == id }) else { return }
            do {
                var changed = try await Task.detached(priority: .userInitiated) { try await change(page, processor, scanID) }.value
                guard let index = scan.pages.firstIndex(where: { $0.id == id }) else { return }
                let replaced = scan.pages[index]
                changed.revision = replaced.revision + 1
                scan.pages[index] = changed
                if save(), changed.crop != replaced.crop { try? FileManager.default.removeItem(at: store.flatURL(scanID: scanID, page: replaced)) }
            } catch {
                failure = "The page could not be changed."
            }
        }
    }

    // MARK: Name, PDF, sending

    public func rename(_ title: String) {
        scan.title = finalName(title)
        scan.isNamedByUser = true
        scan.remembered.remove(.name)
        let pattern = learnedPattern(for: scan.title)
        settings.learn(keys: scan.issuerKeys, label: scan.details.issuer) { $0.name = pattern }
        applyFileName()
    }

    /// Forgets what was remembered for the issuer, and puts back what was read on the page for this scan; the name follows when it was the remembered one or a suggestion.
    public func forget(_ values: Set<RememberedValue>) {
        settings.forget(values, keys: scan.issuerKeys)
        let restored = values.intersection(scan.remembered)
        guard !restored.isEmpty else { return }
        if restored.contains(.owner) { scan.owner = ScanOwner(id: settings.value.defaultOwnerID, isDefault: true) }
        var details = scan.details
        var parts = scan.suggestedParts
        if let read = scan.read {
            if restored.contains(.issuer) {
                details.issuer = read.details.issuer
                parts.issuer = read.parts.issuer
            }
            if restored.contains(.category) { details.category = read.details.category }
        }
        let followsSuggestion = restored.contains(.name) || (!scan.isNamedByUser && scan.title == scan.suggestions.first)
        let names = FileNamer.names(for: parts, date: scan.created)
        scan.details = details
        scan.suggestedParts = parts
        scan.suggestions = names
        if followsSuggestion, let first = names.first { scan.title = first }
        scan.remembered.subtract(restored)
        applyFileName()
    }

    /// Renames the scan only when the user changed the name they were shown, so a name read meanwhile stays.
    public func applyName(_ name: String, shownName: String) {
        if name != shownName || scan.isNamedByUser { rename(name) }
    }

    /// The parts of the file name a name gives, and where each comes from.
    public func fileNameSegments(for title: String) -> [FileNameSegment] {
        let isSuggested = (!scan.isNamedByUser && title == scan.title) || scan.suggestions.contains(title)
        return fileNameFormat.segments(name: title, details: scan.details, scanDate: scan.created, suggestedParts: isSuggested ? scan.suggestedParts : nil)
    }

    /// What the next documents from the same issuer will be named after this name; nil when the name is the suggestion or the issuer cannot be recognized again.
    public func learnedPattern(for title: String) -> NamePattern? {
        guard learnsIssuer, !title.isEmpty, title != scan.suggestions.first else { return nil }
        return NamePattern(name: title, details: scan.details, date: scan.details.date ?? scan.created)
    }

    /// Whether corrections can be reused for the next documents from the same issuer.
    public var learnsIssuer: Bool { !scan.issuerKeys.isEmpty }

    /// Changes the details; a new issuer or category is learned for the next document from the same issuer.
    public func setDetails(_ details: DocumentDetails) {
        guard details != scan.details else { return }
        let old = scan.details
        if details.issuer != old.issuer || details.category != old.category {
            settings.learn(keys: scan.issuerKeys, label: details.issuer) { learned in
                if details.issuer != old.issuer { learned.issuer = details.issuer }
                if details.category != old.category { learned.category = details.category }
            }
        }
        if details.issuer != old.issuer { scan.remembered.remove(.issuer) }
        if details.category != old.category { scan.remembered.remove(.category) }
        resuggestNames(from: old, to: details)
        scan.details = details
        scan.areDetailsEditedByUser = true
        applyFileName()
    }

    /// Suggested names follow a corrected issuer or number, and so does the name while it is the first suggestion.
    /// An issuer joins the suggestions only when they had the one read, or none was read.
    private func resuggestNames(from old: DocumentDetails, to details: DocumentDetails) {
        var parts = scan.suggestedParts
        if details.issuer != old.issuer, parts.issuer != nil || old.issuer == nil { parts.issuer = details.issuer }
        if details.number != old.number { parts.number = details.number }
        guard parts != scan.suggestedParts else { return }
        let followsSuggestion = !scan.isNamedByUser && scan.title == scan.suggestions.first
        let names = FileNamer.names(for: parts, date: scan.created)
        scan.suggestedParts = parts
        scan.suggestions = names
        if followsSuggestion, let first = names.first { scan.title = first }
    }

    /// Derives the file name from the name and details, after a change of either.
    public func applyFileName() {
        let old = scan.fileName
        scan.name = store.availableName(fileName(for: scan.title), for: scan, separator: fileNameFormat.separator.character)
        if !old.isEmpty { store.movePDF(from: old, to: scan) }
        save()
    }

    /// The lines of the page are linked to the owner the scan went out with, unless nothing told it and it only got the default owner.
    public func markSent(_ method: SendMethod) {
        scan.sent = Sent(date: now(), method: method)
        if !hasDefaultOwner { settings.link(lines: scan.headerLines, to: owner.id) }
        save()
    }

    /// Gives the scan to another owner, renamed with its format; the owner is reused for the next documents from the same issuer.
    /// The lines of a scan already sent move to the new owner.
    public func setOwner(_ id: UUID) {
        guard settings.value.hasOwner(id), id != scan.owner?.id || hasDefaultOwner else { return }
        settings.learn(keys: scan.issuerKeys, label: scan.details.issuer) { $0.owner = id }
        if scan.sent != nil { settings.link(lines: scan.headerLines, to: id, replacing: hasDefaultOwner ? nil : owner.id) }
        give(to: ScanOwner(id: id))
    }

    /// Gives the scan to another owner without learning anything, as when its owner is deleted; a scan that got the default owner keeps saying so.
    func assignOwner(_ id: UUID) {
        give(to: ScanOwner(id: id, isDefault: hasDefaultOwner))
    }

    private func give(to owner: ScanOwner) {
        scan.owner = owner
        scan.remembered.remove(.owner)
        applyFileName()
    }

    /// Makes the PDF unless it is current, after the build in progress; cancelling the caller stops the build at the next page.
    public func buildPDF(delay: Duration = .milliseconds(200)) async {
        guard !scan.pages.isEmpty else {
            pdf = .idle
            return
        }
        guard !hasCurrentPDFOnDisk else { return }
        pdf = .building
        try? await Task.sleep(for: delay)
        while let running = pdfBuild {
            await running.value
            if pdfBuild == running { pdfBuild = nil }
        }
        guard !Task.isCancelled, !hasCurrentPDFOnDisk else { return }
        let build = Task { await makePDF() }
        pdfBuild = build
        await withTaskCancellationHandler { await build.value } onCancel: { build.cancel() }
        if pdfBuild == build { pdfBuild = nil }
    }

    /// Keeps the PDF only while the scan is still as it was made from, even when the build was cancelled after its last page.
    private func makePDF() async {
        let makePDFData = makePDFData, scan = scan, inputs = pdfInputs, url = store.pdfURL(of: scan), gate = processor.gate
        do {
            let data = try await makePDFData(scan)
            guard !isDeleted, pdfInputs == inputs else { return }
            try await gate.finish { try await Self.write(data, to: url) }
            guard !isDeleted, store.pdfURL(of: self.scan) == url else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            guard pdfInputs == inputs else { return }
            pdf = .ready(url: url, size: data.count)
            pdfMadeFrom = inputs
        } catch {
            if !Task.isCancelled { pdf = .failed }
        }
    }

    @concurrent
    private static func write(_ data: Data, to url: URL) async throws {
        try data.write(to: url, options: .atomic)
    }

    /// Whether the PDF is made, from the pages and name as they are now.
    public var hasCurrentPDF: Bool {
        if case .ready = pdf { !isBusy && pdfMadeFrom == pdfInputs } else { false }
    }

    /// Whether the current PDF is still there, as Files can delete or rename it.
    private var hasCurrentPDFOnDisk: Bool {
        guard hasCurrentPDF, case .ready(let url, _) = pdf else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Makes the PDF once every page and edit is done, unless the one already made is current; called before sending.
    public func preparePDF() async {
        await waitUntilIdle()
        await buildPDF(delay: .zero)
    }

    /// Deletes the scan; pages still being processed are dropped when they finish, then their files are deleted too.
    public func delete() {
        isDeleted = true
        pdfBuild?.cancel()
        store.delete(scan)
        let store = store, scan = scan, previous = queue
        queue = Task {
            await previous?.value
            store.delete(scan)
        }
    }

    public func dismissFailure() { failure = nil }

    /// Sets the issuer or the number as typed: trimmed, removed when blank.
    public func setDetail(_ detail: WritableKeyPath<DocumentDetails, String?>, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var details = scan.details
        details[keyPath: detail] = trimmed.isEmpty ? nil : trimmed
        setDetails(details)
    }

    @discardableResult
    private func save() -> Bool {
        guard !isEmpty, !isDeleted else { return false }
        do {
            try store.save(scan)
            didSave?()
            return true
        } catch {
            failure = "The scan could not be saved."
            return false
        }
    }
}
