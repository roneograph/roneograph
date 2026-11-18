import CoreImage
import Foundation

/// Turns photos into scan pages and scans into PDFs, reading and writing the page files through the store.
public struct ScanProcessor: Sendable {
    public let store: ScanStore
    private let extractor: PageExtractor
    private let cleaner: PageCleaner
    private let writer: PDFWriter
    private let readText: @Sendable (CIImage) async throws -> [TextLine]
    private let detectionSize: CGFloat = 1600
    private let previewSize: CGFloat = 1200
    /// Shared by every scan: callers run adding, recropping, previewing and reading a page in it, and the PDF runs each of its pages in it.
    public let gate: ProcessingGate
    /// The paper of pages whose size is not clear from their proportions.
    public let paper: Paper

    /// Renders on a context of its own: concurrent renders on one context can change pixels, and only the work in the gate is kept from running at once.
    /// `readText` reads the lines of text of a cleaned page.
    public init(store: ScanStore, paper: Paper = Paper(region: Locale.current.region), background: (any BackgroundActivity)? = nil, readText: @escaping @Sendable (CIImage) async throws -> [TextLine] = { try await TextReader().lines(in: $0) }) {
        let context = CIContext(options: [.cacheIntermediates: false])
        self.store = store
        self.paper = paper
        gate = ProcessingGate(background: background)
        extractor = PageExtractor(context: context)
        cleaner = PageCleaner(context: context)
        writer = PDFWriter(context: context)
        self.readText = readText
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

    /// Flattens the page again from the original photo with another outline, nil for the whole photo, and analyzes it again; the flat page it replaces is kept.
    public func recrop(_ page: ScanPage, scanID: UUID, quad: Quad?) async throws -> ScanPage {
        guard let photo = CIImage(contentsOf: store.photoURL(scanID: scanID, pageID: page.id), options: [.applyOrientationProperty: true]) else {
            throw ProcessingError.unreadablePhoto
        }
        return try await flatten(photo, quad: quad, scanID: scanID) { analysis in
            var updated = page
            updated.quad = quad
            updated.analysis = analysis
            updated.crop += 1
            return updated
        }
    }

    /// Cuts the page out of the photo, then saves the flat page and its preview for the page `makePage` builds from the analysis.
    private func flatten(_ photo: CIImage, quad: Quad?, scanID: UUID, makePage: (PageAnalysis) -> ScanPage) async throws -> ScanPage {
        let flat = quad.map { extractor.correct(photo, quad: $0) } ?? photo
        let page = makePage(try await cleaner.analyze(flat))
        guard let data = extractor.jpegData(of: flat, quality: 0.9) else { throw ProcessingError.cannotEncode }
        try data.write(to: store.flatURL(scanID: scanID, page: page), options: .atomic)
        try writePreview(of: page, scanID: scanID, flat: flat)
        return page
    }

    /// Writes the small cleaned image shown in the app, after any change to the page.
    public func writePreview(of page: ScanPage, scanID: UUID, flat: CIImage? = nil) throws {
        guard let flat = flat ?? CIImage(contentsOf: store.flatURL(scanID: scanID, page: page)) else { throw ProcessingError.unreadablePage }
        let clean = cleaner.render(flat.scaledKeepingEdges(by: flat.scale(toLongSide: previewSize)), analysis: page.analysis, look: page.look)
        guard let data = extractor.jpegData(of: clean, quality: 0.8) else { throw ProcessingError.cannotEncode }
        try data.write(to: store.previewURL(scanID: scanID, pageID: page.id), options: .atomic)
    }

    /// The details of the document, the words to name it after and the owner it is addressed to, from the text of the page as the PDF has it.
    public func detectDocument(on page: ScanPage, scanID: UUID, owners: OwnerMatcher = OwnerMatcher()) async throws -> DetectedDocument? {
        guard let flat = CIImage(contentsOf: store.flatURL(scanID: scanID, page: page)) else { return nil }
        return try await detectDocument(on: page, flat: flat, scanID: scanID, owners: owners)
    }

    /// The same from the flat page given, as page-cleanup does with pages that do not come from a photo.
    public func detectDocument(on page: ScanPage, flat: CIImage, scanID: UUID, owners: OwnerMatcher = OwnerMatcher()) async throws -> DetectedDocument {
        let image = cleaner.render(flat, analysis: page.analysis, look: page.look)
        return DocumentDetector().detect(lines: try await text(of: page, scanID: scanID, rendered: image), owners: owners, aspectRatio: image.extent.width / image.extent.height)
    }

    /// The text of the cleaned page, read once for each way it is cut and turned and kept with the scan; a reading that fails is tried again the next time.
    private func text(of page: ScanPage, scanID: UUID, rendered: CIImage) async throws -> [TextLine] {
        if let text = store.text(of: page, scanID: scanID) { return text }
        let text = try await readText(rendered)
        try? store.saveText(text, of: page, scanID: scanID)
        return text
    }

    /// Renders, reads and writes one page after the other, so only one page image is in memory at a time.
    @concurrent
    public func pdfData(of scan: Scan) async throws -> Data {
        let document = try writer.document(title: scan.title, defaultPaper: paper)
        for page in scan.pages {
            try await gate.run {
                try Task.checkCancellation()
                guard let flat = CIImage(contentsOf: store.flatURL(scanID: scan.id, page: page)) else { throw ProcessingError.unreadablePage }
                let image = cleaner.render(flat, analysis: page.analysis, look: page.look)
                let text = try await text(of: page, scanID: scan.id, rendered: image)
                try document.add(PDFPageContent(image: image, look: page.look, textLineHeight: page.analysis.textLineHeight, text: text))
            }
        }
        return document.close()
    }
}
