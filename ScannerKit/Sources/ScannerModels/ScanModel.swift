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
        var pages: [ScanPage]
        var quality: PDFQuality
        var paper: Paper
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
    public var quality: PDFQuality { scan.quality ?? settings.value.quality }
    public var pdfInputs: PDFInputs { PDFInputs(name: scan.name, pages: scan.pages, quality: quality, paper: settings.value.paper) }
    public var fallbackTitle: String { namer.fallback(for: scan.created) }
    public var isBusy: Bool { processing > 0 || updating > 0 }

    /// The file name a name gets with the format from the settings, before avoiding collisions.
    public func fileName(for title: String) -> String {
        settings.value.fileNameFormat.fileName(name: title, date: scan.fileDate)
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
        let processor = processor, scanID = scan.id, look = settings.value.look
        enqueue { [self] in
            defer { processing -= 1 }
            do {
                let page = try await Task.detached(priority: .userInitiated) {
                    try processor.addPage(photo: data, liveQuad: liveQuad, scanID: scanID, look: look)
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

    private func suggestNames(from page: ScanPage) async {
        let processor = processor, scanID = scan.id, date = scan.created
        guard let suggestions = await Task.detached(priority: .userInitiated, operation: {
            processor.nameSuggestions(for: page, scanID: scanID, date: date)
        }).value, !isDeleted else { return }
        scan.suggestions = suggestions.names
        scan.documentDate = suggestions.date
        if !scan.isNamedByUser, let first = suggestions.names.first {
            scan.title = first
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

    public func rotatePage(_ id: UUID, clockwise: Bool) {
        editPage(id) { $0.rotate(clockwise: clockwise) }
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
        applyFileName()
    }

    /// Derives the file name from the name, after a rename or a change of format in Settings.
    public func applyFileName() {
        let old = scan.name
        scan.name = store.availableName(fileName(for: scan.title), for: scan, separator: settings.value.fileNameFormat.separator.character)
        if !old.isEmpty { store.movePDF(from: old, to: scan) }
        save()
    }

    public func setQuality(_ quality: PDFQuality) {
        scan.quality = quality == settings.value.quality ? nil : quality
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
        let processor = processor, scan = scan, quality = quality, paper = settings.value.paper
        do {
            let data = try await Task.detached(priority: .userInitiated) { try processor.pdfData(of: scan, quality: quality, paper: paper) }.value
            guard !Task.isCancelled, !isDeleted else { return }
            let url = store.pdfURL(of: scan)
            try data.write(to: url, options: .atomic)
            pdf = .ready(url: url, size: data.count)
        } catch {
            pdf = .failed
        }
    }

    /// Sizes of the PDF in every quality, for the options sheet.
    public func pdfSizes() async -> [PDFQuality: Int] {
        let processor = processor, scan = scan, paper = settings.value.paper
        return await Task.detached(priority: .userInitiated) {
            var sizes: [PDFQuality: Int] = [:]
            for quality in PDFQuality.allCases {
                sizes[quality] = try? processor.pdfData(of: scan, quality: quality, paper: paper).count
            }
            return sizes
        }.value
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
