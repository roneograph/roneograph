import CoreImage
import Foundation

/// Turns photos into scan pages and scans into PDFs, reading and writing the page files through the store.
public struct ScanProcessor: @unchecked Sendable {
    public let store: ScanStore
    private let extractor: PageExtractor
    private let cleaner: PageCleaner
    private let writer: PDFWriter
    private let reader: TextReader
    public var detectionSize: CGFloat = 1600
    public var previewSize: CGFloat = 1200

    public init(store: ScanStore, context: CIContext) {
        self.store = store
        extractor = PageExtractor(context: context)
        cleaner = PageCleaner(context: context)
        writer = PDFWriter(context: context)
        reader = TextReader()
    }

    public enum ProcessingError: Error {
        case unreadablePhoto, unreadablePage, cannotEncode
    }

    /// Finds the page again on the full photo (the live outline as a fallback), flattens and analyzes it, and saves the photo, the flat page and a preview.
    public func addPage(photo data: Data, liveQuad: Quad?, scanID: UUID, look: PageLook?) throws -> ScanPage {
        guard let photo = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw ProcessingError.unreadablePhoto }
        let scale = min(1, detectionSize / max(photo.extent.width, photo.extent.height))
        let quad = extractor.detect(in: photo.transformed(by: CGAffineTransform(scaleX: scale, y: scale))) ?? liveQuad
        let flat = quad.map { extractor.correct(photo, quad: $0) } ?? photo
        let page = ScanPage(quad: quad, analysis: cleaner.analyze(flat), cleanup: CleanupSettings(look: look))

        try FileManager.default.createDirectory(at: store.directory(of: scanID), withIntermediateDirectories: true)
        try data.write(to: store.photoURL(scanID: scanID, pageID: page.id))
        guard let flatData = extractor.jpegData(of: flat, quality: 0.9) else { throw ProcessingError.cannotEncode }
        try flatData.write(to: store.flatURL(scanID: scanID, pageID: page.id))
        try writePreview(of: page, scanID: scanID, flat: flat)
        return page
    }

    /// Flattens the page again from the original photo with another outline, nil for the whole photo, and analyzes it again.
    public func recrop(_ page: ScanPage, scanID: UUID, quad: Quad?) throws -> ScanPage {
        guard let photo = CIImage(contentsOf: store.photoURL(scanID: scanID, pageID: page.id), options: [.applyOrientationProperty: true]) else {
            throw ProcessingError.unreadablePhoto
        }
        let flat = quad.map { extractor.correct(photo, quad: $0) } ?? photo
        var updated = page
        updated.quad = quad
        updated.analysis = cleaner.analyze(flat)
        guard let flatData = extractor.jpegData(of: flat, quality: 0.9) else { throw ProcessingError.cannotEncode }
        try flatData.write(to: store.flatURL(scanID: scanID, pageID: page.id), options: .atomic)
        try writePreview(of: updated, scanID: scanID, flat: flat)
        return updated
    }

    /// Writes the small cleaned image shown in the app, after any change to the page.
    public func writePreview(of page: ScanPage, scanID: UUID, flat: CIImage? = nil) throws {
        guard let flat = flat ?? CIImage(contentsOf: store.flatURL(scanID: scanID, pageID: page.id)) else { throw ProcessingError.unreadablePage }
        let scale = min(1, previewSize / max(flat.extent.width, flat.extent.height))
        let clean = cleaner.render(flat.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), analysis: page.analysis, settings: page.cleanup)
        guard let data = extractor.jpegData(of: clean, quality: 0.8) else { throw ProcessingError.cannotEncode }
        try data.write(to: store.previewURL(scanID: scanID, pageID: page.id), options: .atomic)
    }

    /// Name suggestions and the document date, from the text of the page.
    public func nameSuggestions(for page: ScanPage, scanID: UUID, date: Date) -> NameSuggestions? {
        guard let preview = CIImage(contentsOf: store.previewURL(scanID: scanID, pageID: page.id)) else { return nil }
        return FileNamer().suggestions(lines: reader.lines(in: preview), date: date)
    }

    public func pdfData(of scan: Scan, quality: PDFQuality, paper: Paper) throws -> Data {
        let pages = try scan.pages.map { page in
            guard let flat = CIImage(contentsOf: store.flatURL(scanID: scan.id, pageID: page.id)) else { throw ProcessingError.unreadablePage }
            return PDFPageContent(image: cleaner.render(flat, analysis: page.analysis, settings: page.cleanup), look: page.look, textLineHeight: page.analysis.textLineHeight)
        }
        return try writer.data(pages: pages, title: scan.title, quality: quality, defaultPaper: paper)
    }
}
