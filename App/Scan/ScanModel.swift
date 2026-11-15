import Foundation
import Observation
import ScannerKit

/// One scan while it is captured, reviewed and sent; every change is saved right away.
@MainActor @Observable
final class ScanModel {
    enum PDFState: Equatable {
        case idle, building, failed
        case ready(url: URL, size: Int)
    }

    /// What the PDF depends on; a change triggers a new PDF.
    struct PDFInputs: Equatable {
        var name: String
        var pages: [ScanPage]
        var quality: PDFQuality
        var paper: Paper
    }

    private(set) var scan: Scan
    private(set) var processing = 0
    private(set) var pdf = PDFState.idle
    private(set) var failure: String?
    let processor: ScanProcessor
    let settings: SettingsStore
    private var chain: Task<Void, Never>?
    private let namer = FileNamer()

    init(scan: Scan, processor: ScanProcessor, settings: SettingsStore) {
        self.scan = scan
        self.processor = processor
        self.settings = settings
    }

    var store: ScanStore { processor.store }
    var quality: PDFQuality { scan.quality ?? settings.value.quality }
    var pdfInputs: PDFInputs { PDFInputs(name: scan.name, pages: scan.pages, quality: quality, paper: settings.value.paper) }
    var fallbackName: String { namer.fallback(for: scan.created) }

    func previewURL(of page: ScanPage) -> URL { store.previewURL(scanID: scan.id, pageID: page.id) }

    // MARK: Capture

    /// Pages are processed one at a time, in the order they were captured.
    func addPhoto(_ data: Data, liveQuad: Quad?) {
        processing += 1
        let previous = chain
        let processor = processor, scanID = scan.id, look = settings.value.look
        chain = Task {
            await previous?.value
            defer { processing -= 1 }
            do {
                let page = try await Task.detached(priority: .userInitiated) {
                    try processor.addPage(photo: data, liveQuad: liveQuad, scanID: scanID, look: look)
                }.value
                scan.pages.append(page)
                save()
                if scan.pages.count == 1 { await suggestNames(from: page) }
            } catch {
                failure = "A page could not be processed."
            }
        }
    }

    func finishCapture() {
        scan.isFinished = true
        save()
    }

    private func suggestNames(from page: ScanPage) async {
        let processor = processor, scanID = scan.id, date = scan.created, style = settings.value.fileNameStyle
        let suggestions = await Task.detached(priority: .userInitiated) {
            processor.nameSuggestions(for: page, scanID: scanID, date: date, style: style)
        }.value
        scan.suggestions = suggestions
        if !scan.isNamedByUser, let first = suggestions.first {
            setName(first)
        }
        save()
    }

    // MARK: Pages

    func deletePage(_ id: UUID) {
        scan.pages.removeAll { $0.id == id }
        store.deletePageFiles(scanID: scan.id, pageID: id)
        save()
    }

    /// Moves a page to the place of another one, as when dropping it there.
    func movePage(_ id: UUID, to target: UUID) {
        guard let from = scan.pages.firstIndex(where: { $0.id == id }), let to = scan.pages.firstIndex(where: { $0.id == target }), from != to else { return }
        scan.pages.insert(scan.pages.remove(at: from), at: to)
        save()
    }

    func rotatePage(_ id: UUID, clockwise: Bool) {
        update(id) { $0.rotate(clockwise: clockwise) }
    }

    func setLook(_ look: PageLook?, of ids: [UUID]) {
        for id in ids {
            update(id) { $0.cleanup.look = look }
        }
    }

    /// Applies the change, renders the preview again, then publishes the page with a new revision so its image reloads.
    private func update(_ id: UUID, _ change: (inout ScanPage) -> Void) {
        guard let index = scan.pages.firstIndex(where: { $0.id == id }) else { return }
        var page = scan.pages[index]
        change(&page)
        processing += 1
        let processor = processor, scanID = scan.id, changed = page
        Task {
            defer { processing -= 1 }
            try? await Task.detached(priority: .userInitiated) { try processor.writePreview(of: changed, scanID: scanID) }.value
            guard let index = scan.pages.firstIndex(where: { $0.id == id }) else { return }
            var published = changed
            published.revision = scan.pages[index].revision + 1
            scan.pages[index] = published
            save()
        }
    }

    // MARK: Name, PDF, sending

    func rename(_ name: String) {
        setName(namer.finalName(name, fallback: scan.suggestions.first ?? fallbackName))
        scan.isNamedByUser = true
        save()
    }

    private func setName(_ name: String) {
        let old = scan.name
        scan.name = store.availableName(name, for: scan)
        store.movePDF(from: old, to: scan)
    }

    func setQuality(_ quality: PDFQuality) {
        scan.quality = quality == settings.value.quality ? nil : quality
        save()
    }

    func markSent() {
        scan.sent = .now
        save()
    }

    func buildPDF() async {
        guard !scan.pages.isEmpty else {
            pdf = .idle
            return
        }
        pdf = .building
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let processor = processor, scan = scan, quality = quality, paper = settings.value.paper
        do {
            let data = try await Task.detached(priority: .userInitiated) { try processor.pdfData(of: scan, quality: quality, paper: paper) }.value
            guard !Task.isCancelled else { return }
            let url = store.pdfURL(of: scan)
            try data.write(to: url, options: .atomic)
            pdf = .ready(url: url, size: data.count)
        } catch {
            pdf = .failed
        }
    }

    /// Sizes of the PDF in every quality, for the options sheet.
    func pdfSizes() async -> [PDFQuality: Int] {
        let processor = processor, scan = scan, paper = settings.value.paper
        return await Task.detached(priority: .userInitiated) {
            var sizes: [PDFQuality: Int] = [:]
            for quality in PDFQuality.allCases {
                sizes[quality] = try? processor.pdfData(of: scan, quality: quality, paper: paper).count
            }
            return sizes
        }.value
    }

    func delete() {
        chain?.cancel()
        store.delete(scan)
    }

    func dismissFailure() { failure = nil }

    private func save() {
        guard !scan.pages.isEmpty else { return }
        do {
            try store.save(scan)
        } catch {
            failure = "The scan could not be saved."
        }
    }
}
