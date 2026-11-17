import CoreImage
import Foundation

/// Turns photos into scan pages and scans into PDFs, reading and writing the page files through the store.
public struct ScanProcessor: Sendable {
    public let store: ScanStore
    private let extractor: PageExtractor
    private let cleaner: PageCleaner
    private let writer: PDFWriter
    private let reader: TextReader
    private let texts = PageTextCache()
    private let detectionSize: CGFloat = 1600
    private let previewSize: CGFloat = 1200
    /// Shared by every scan: callers run adding, recropping, previewing and reading a page in it, and the PDF runs each of its pages in it.
    public let gate: ProcessingGate
    /// The paper of pages whose size is not clear from their proportions.
    public let paper: Paper

    public init(store: ScanStore, context: CIContext, paper: Paper = Paper(region: Locale.current.region), background: (any BackgroundActivity)? = nil) {
        self.store = store
        self.paper = paper
        gate = ProcessingGate(background: background)
        extractor = PageExtractor(context: context)
        cleaner = PageCleaner(context: context)
        writer = PDFWriter(context: context)
        reader = TextReader()
    }

    public enum ProcessingError: Error {
        case unreadablePhoto, unreadablePage, cannotEncode
    }

    /// Finds the page again on its saved photo (the live outline as a fallback), flattens and analyzes it, and saves the flat page and a preview.
    public func addPage(_ pending: PendingPage, scanID: UUID) async throws -> ScanPage {
        guard let photo = CIImage(contentsOf: store.photoURL(scanID: scanID, pageID: pending.id), options: [.applyOrientationProperty: true]) else {
            throw ProcessingError.unreadablePhoto
        }
        let quad = await extractor.detect(in: photo.scaled(by: photo.scale(toLongSide: detectionSize))) ?? pending.liveQuad
        return try await flatten(photo, quad: quad, scanID: scanID) { ScanPage(id: pending.id, quad: quad, analysis: $0) }
    }

    /// Flattens the page again from the original photo with another outline, nil for the whole photo, and analyzes it again.
    public func recrop(_ page: ScanPage, scanID: UUID, quad: Quad?) async throws -> ScanPage {
        guard let photo = CIImage(contentsOf: store.photoURL(scanID: scanID, pageID: page.id), options: [.applyOrientationProperty: true]) else {
            throw ProcessingError.unreadablePhoto
        }
        return try await flatten(photo, quad: quad, scanID: scanID) { analysis in
            var updated = page
            updated.quad = quad
            updated.analysis = analysis
            return updated
        }
    }

    /// Cuts the page out of the photo, then saves the flat page and its preview for the page `makePage` builds from the analysis.
    private func flatten(_ photo: CIImage, quad: Quad?, scanID: UUID, makePage: (PageAnalysis) -> ScanPage) async throws -> ScanPage {
        let flat = quad.map { extractor.correct(photo, quad: $0) } ?? photo
        let page = makePage(try await cleaner.analyze(flat))
        guard let data = extractor.jpegData(of: flat, quality: 0.9) else { throw ProcessingError.cannotEncode }
        try data.write(to: store.flatURL(scanID: scanID, pageID: page.id), options: .atomic)
        try writePreview(of: page, scanID: scanID, flat: flat)
        return page
    }

    /// Writes the small cleaned image shown in the app, after any change to the page.
    public func writePreview(of page: ScanPage, scanID: UUID, flat: CIImage? = nil) throws {
        guard let flat = flat ?? CIImage(contentsOf: store.flatURL(scanID: scanID, pageID: page.id)) else { throw ProcessingError.unreadablePage }
        let clean = cleaner.render(flat.scaled(by: flat.scale(toLongSide: previewSize)), analysis: page.analysis, look: page.look)
        guard let data = extractor.jpegData(of: clean, quality: 0.8) else { throw ProcessingError.cannotEncode }
        try data.write(to: store.previewURL(scanID: scanID, pageID: page.id), options: .atomic)
    }

    /// The details of the document and the words to name it after, from the text of the page; `ownLines` are never taken as the issuer.
    public func detectDocument(on page: ScanPage, scanID: UUID, ownLines: Set<String> = []) async throws -> DetectedDocument? {
        guard let preview = CIImage(contentsOf: store.previewURL(scanID: scanID, pageID: page.id)) else { return nil }
        return DocumentDetector().detect(lines: try await reader.lines(in: preview), ownLines: ownLines, aspectRatio: preview.extent.width / preview.extent.height)
    }

    /// Renders, reads and writes one page after the other, so only one page image is in memory at a time.
    @concurrent
    public func pdfData(of scan: Scan) async throws -> Data {
        let document = try writer.document(title: scan.title, defaultPaper: paper)
        for page in scan.pages {
            try await gate.run {
                try Task.checkCancellation()
                guard let flat = CIImage(contentsOf: store.flatURL(scanID: scan.id, pageID: page.id)) else { throw ProcessingError.unreadablePage }
                let image = cleaner.render(flat, analysis: page.analysis, look: page.look)
                let text = try await texts.lines(of: page) { try await reader.lines(in: image) }
                try document.add(PDFPageContent(image: image, look: page.look, textLineHeight: page.analysis.textLineHeight, text: text))
            }
        }
        return document.close()
    }
}
