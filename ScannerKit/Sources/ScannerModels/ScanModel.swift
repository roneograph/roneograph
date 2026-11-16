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
    /// Pages captured but not processed yet.
    public private(set) var processing = 0
    /// Page edits not applied yet.
    public private(set) var updating = 0
    public private(set) var pdf = PDFState.idle
    public private(set) var failure: String?
    public let processor: ScanProcessor
    public let settings: SettingsStore
    /// Called after every save, so the list of scans stays current.
    var didSave: (() -> Void)?
    private var queue: Task<Void, Never>?
    private var isDeleted = false
    private let namer = FileNamer()
    private let now: @Sendable () -> Date

    public init(scan: Scan, processor: ScanProcessor, settings: SettingsStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.id = scan.id
        self.scan = scan
        self.processor = processor
        self.settings = settings
        self.now = now
    }

    public var store: ScanStore { processor.store }
    public var pdfInputs: PDFInputs { PDFInputs(name: scan.fileName, title: scan.title, pages: scan.pages) }
    public var fallbackTitle: String { namer.fallback(for: scan.created) }
    public var isBusy: Bool { processing > 0 || updating > 0 }

    /// The file name a name and details get with the format from the settings, before avoiding collisions.
    /// A name the user typed is kept as typed; a suggested one leaves out what a custom format already shows.
    public func fileName(for title: String) -> String {
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

    // MARK: Capture

    public func addPhoto(_ data: Data, liveQuad: Quad?) {
        processing += 1
        let processor = processor, scanID = scan.id
        enqueue { [self] in
            defer { processing -= 1 }
            do {
                let page = try await Task.detached(priority: .userInitiated) {
                    try processor.addPage(photo: data, liveQuad: liveQuad, scanID: scanID)
                }.value
                guard !isDeleted else { return }
                scan.pages.append(page)
                save()
                if scan.pages.count == 1 { await suggestNames(from: page) }
            } catch {
                failure = "A page could not be processed."
            }
        }
    }

    public func finishCapture() {
        scan.isFinished = true
        save()
    }

    /// Reads the details and names on the first page; what the user corrected for the same issuer before wins over what was read.
    private func suggestNames(from page: ScanPage) async {
        let processor = processor, scanID = scan.id, date = scan.created, ownLines = settings.ownLines
        guard let read = await Task.detached(priority: .userInitiated, operation: {
            processor.nameSuggestions(for: page, scanID: scanID, date: date, ownLines: ownLines)
        }).value, !isDeleted else { return }
        var document = read.document
        settings.recordHeaderLines(document.headerLines, issuerEvidence: document.issuerEvidence)
        if let learned = settings.learnedIssuer(for: document.issuerKeys) {
            document.details.issuer = learned.issuer
            document.details.category = learned.category
            document.parts.issuer = learned.issuer
        }
        let suggestions = namer.suggestions(for: document, date: date)
        scan.suggestions = suggestions.names
        scan.suggestedParts = document.parts
        scan.issuerKeys = document.issuerKeys
        if !scan.areDetailsEditedByUser { scan.details = document.details }
        if !scan.isNamedByUser, let first = suggestions.names.first {
            scan.title = settings.learnedName(for: first) ?? first
        }
        applyFileName()
    }

    // MARK: Pages

    public func deletePage(_ id: UUID) {
        scan.pages.removeAll { $0.id == id }
        store.deletePageFiles(scanID: scan.id, pageID: id)
        save()
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
            try processor.recrop(page, scanID: scanID, quad: quad)
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
    private func update(_ id: UUID, _ change: @escaping @Sendable (ScanPage, ScanProcessor, UUID) throws -> ScanPage) {
        updating += 1
        let processor = processor, scanID = scan.id
        enqueue { [self] in
            defer { updating -= 1 }
            guard let page = scan.pages.first(where: { $0.id == id }) else { return }
            do {
                var changed = try await Task.detached(priority: .userInitiated) { try change(page, processor, scanID) }.value
                guard let index = scan.pages.firstIndex(where: { $0.id == id }) else { return }
                changed.revision = scan.pages[index].revision + 1
                scan.pages[index] = changed
                save()
            } catch {
                failure = "The page could not be changed."
            }
        }
    }

    // MARK: Name, PDF, sending

    public func rename(_ title: String) {
        scan.title = namer.finalName(title, fallback: scan.suggestions.first ?? fallbackTitle)
        scan.isNamedByUser = true
        if let suggestion = scan.suggestions.first, suggestion != fallbackTitle {
            settings.learn(scan.title, for: suggestion)
        }
        applyFileName()
    }

    /// Renames the scan only when the user changed the name they were shown, so a name read meanwhile stays.
    public func applyName(_ name: String, shownName: String) {
        if name != shownName || scan.isNamedByUser { rename(name) }
    }

    /// The parts of the file name a name gives, and where each comes from.
    public func fileNameSegments(for title: String) -> [FileNameSegment] {
        let isSuggested = (!scan.isNamedByUser && title == scan.title) || scan.suggestions.contains(title)
        return settings.value.fileNameFormat.segments(name: title, details: scan.details, scanDate: scan.created, suggestedParts: isSuggested ? scan.suggestedParts : nil)
    }

    /// The suggestion a name would be learned for, when the name differs from it.
    public func learnedSuggestion(for title: String) -> String? {
        guard let suggestion = scan.suggestions.first, suggestion != fallbackTitle, suggestion != title else { return nil }
        return suggestion
    }

    /// Whether a new issuer or category can be reused for the next documents from the same issuer.
    public var learnsIssuer: Bool { !scan.issuerKeys.isEmpty }

    /// Changes the details; a new issuer or category is learned for the next document from the same issuer.
    public func setDetails(_ details: DocumentDetails) {
        guard details != scan.details else { return }
        if details.issuer != scan.details.issuer || details.category != scan.details.category {
            settings.learnIssuer(details.issuer, category: details.category, keys: scan.issuerKeys)
        }
        scan.details = details
        scan.areDetailsEditedByUser = true
        applyFileName()
    }

    /// Derives the file name from the name and details, after a change of either or of the format in Settings.
    public func applyFileName() {
        let old = scan.fileName
        scan.name = store.availableName(fileName(for: scan.title), for: scan, separator: settings.value.fileNameFormat.separator.character)
        if !old.isEmpty { store.movePDF(from: old, to: scan) }
        save()
    }

    public func markSent(_ method: SendMethod) {
        scan.sent = now()
        scan.sentBy = method
        save()
    }

    public func buildPDF(delay: Duration = .milliseconds(200)) async {
        guard !scan.pages.isEmpty else {
            pdf = .idle
            return
        }
        pdf = .building
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        let processor = processor, scan = scan
        do {
            let data = try await Task.detached(priority: .userInitiated) { try processor.pdfData(of: scan) }.value
            guard !Task.isCancelled, !isDeleted else { return }
            let url = store.pdfURL(of: scan)
            try data.write(to: url, options: .atomic)
            pdf = .ready(url: url, size: data.count)
        } catch {
            pdf = .failed
        }
    }

    /// Deletes the scan; pages still being processed are dropped when they finish, then their files are deleted too.
    public func delete() {
        isDeleted = true
        store.delete(scan)
        let store = store, scan = scan, previous = queue
        queue = Task {
            await previous?.value
            store.delete(scan)
        }
    }

    public func dismissFailure() { failure = nil }

    private func save() {
        guard !scan.pages.isEmpty, !isDeleted else { return }
        do {
            try store.save(scan)
            didSave?()
        } catch {
            failure = "The scan could not be saved."
        }
    }
}
