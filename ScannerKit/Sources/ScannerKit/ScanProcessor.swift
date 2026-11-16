import CoreImage
import Foundation

/// Turns photos into scan pages and scans into PDFs, reading and writing the page files through the store.
public struct ScanProcessor: @unchecked Sendable {
    public let store: ScanStore
    private let extractor: PageExtractor
    private let cleaner: PageCleaner
    private let writer: PDFWriter
    private let reader: TextReader
    private let texts = PageTextCache()
    public var detectionSize: CGFloat = 1600
    public var previewSize: CGFloat = 1200
    /// The paper of pages whose size is not clear from their proportions.
    public let paper: Paper

    public init(store: ScanStore, context: CIContext, paper: Paper = Paper(region: Locale.current.region)) {
        self.store = store
        self.paper = paper
        extractor = PageExtractor(context: context)
        cleaner = PageCleaner(context: context)
        writer = PDFWriter(context: context)
        reader = TextReader()
    }

    public enum ProcessingError: Error {
        case unreadablePhoto, unreadablePage, cannotEncode
    }

    /// Finds the page again on the full photo (the live outline as a fallback), flattens and analyzes it, and saves the photo, the flat page and a preview.
    public func addPage(photo data: Data, liveQuad: Quad?, scanID: UUID) throws -> ScanPage {
        guard let photo = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw ProcessingError.unreadablePhoto }
        let quad = extractor.detect(in: photo.scaled(by: photo.scale(toLongSide: detectionSize))) ?? liveQuad
        try FileManager.default.createDirectory(at: store.directory(of: scanID), withIntermediateDirectories: true)
        let page = try flatten(photo, quad: quad, scanID: scanID) { ScanPage(quad: quad, analysis: $0) }
        try data.write(to: store.photoURL(scanID: scanID, pageID: page.id), options: .atomic)
        return page
    }

    /// Flattens the page again from the original photo with another outline, nil for the whole photo, and analyzes it again.
    public func recrop(_ page: ScanPage, scanID: UUID, quad: Quad?) throws -> ScanPage {
        guard let photo = CIImage(contentsOf: store.photoURL(scanID: scanID, pageID: page.id), options: [.applyOrientationProperty: true]) else {
            throw ProcessingError.unreadablePhoto
        }
        return try flatten(photo, quad: quad, scanID: scanID) { analysis in
            var updated = page
            updated.quad = quad
            updated.analysis = analysis
            return updated
        }
    }

    /// Cuts the page out of the photo, then saves the flat page and its preview for the page `makePage` builds from the analysis.
    private func flatten(_ photo: CIImage, quad: Quad?, scanID: UUID, makePage: (PageAnalysis) -> ScanPage) throws -> ScanPage {
        let flat = quad.map { extractor.correct(photo, quad: $0) } ?? photo
        let page = makePage(cleaner.analyze(flat))
        guard let data = extractor.jpegData(of: flat, quality: 0.9) else { throw ProcessingError.cannotEncode }
        try data.write(to: store.flatURL(scanID: scanID, pageID: page.id), options: .atomic)
        try writePreview(of: page, scanID: scanID, flat: flat)
        return page
    }

    /// Writes the small cleaned image shown in the app, after any change to the page.
    public func writePreview(of page: ScanPage, scanID: UUID, flat: CIImage? = nil) throws {
        guard let flat = flat ?? CIImage(contentsOf: store.flatURL(scanID: scanID, pageID: page.id)) else { throw ProcessingError.unreadablePage }
        let clean = cleaner.render(flat.scaled(by: flat.scale(toLongSide: previewSize)), analysis: page.analysis, settings: page.cleanup)
        guard let data = extractor.jpegData(of: clean, quality: 0.8) else { throw ProcessingError.cannotEncode }
        try data.write(to: store.previewURL(scanID: scanID, pageID: page.id), options: .atomic)
    }

    /// Name suggestions and the details of the document, from the text of the page; `ownLines` are never taken as the issuer.
    public func nameSuggestions(for page: ScanPage, scanID: UUID, date: Date, ownLines: Set<String> = []) -> NameSuggestions? {
        guard let preview = CIImage(contentsOf: store.previewURL(scanID: scanID, pageID: page.id)) else { return nil }
        return FileNamer().suggestions(lines: reader.lines(in: preview), date: date, ownLines: ownLines)
    }

    public func pdfData(of scan: Scan) throws -> Data {
        let pages = try scan.pages.map { page in
            guard let flat = CIImage(contentsOf: store.flatURL(scanID: scan.id, pageID: page.id)) else { throw ProcessingError.unreadablePage }
            let image = cleaner.render(flat, analysis: page.analysis, settings: page.cleanup)
            return PDFPageContent(image: image, look: page.look, textLineHeight: page.analysis.textLineHeight, text: texts.lines(of: page) { reader.lines(in: image) })
        }
        return try writer.data(pages: pages, title: scan.title, defaultPaper: paper)
    }
}
