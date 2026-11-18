import CoreImage
import Foundation
import ImageIO
import ScannerKit

// Usage: page-cleanup <output directory> <page images...>
// Writes the automatic result and every look of each page, prints the analysis,
// then writes scan.pdf with all pages in their automatic look.
// The details and the PDF are made by the app's ScanProcessor, on a scan kept in a temporary folder
// whose flat pages are the files given, or the file turned upright when it says it is turned.
let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("Usage: page-cleanup <output directory> <page images...>\n".utf8))
    exit(1)
}
let output = URL(filePath: arguments.first!)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let context = CIContext(options: [.cacheIntermediates: false])
let cleaner = PageCleaner(context: context)
let extractor = PageExtractor(context: context)
let temporary = FileManager.default.temporaryDirectory.appending(path: "page-cleanup-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: temporary) }
let store = ScanStore(scansDirectory: temporary, documentsDirectory: temporary)
let processor = ScanProcessor(store: store, paper: .a4)
var scan = Scan(name: "Scan")
try FileManager.default.createDirectory(at: store.directory(of: scan.id), withIntermediateDirectories: true)

for path in arguments.dropFirst() {
    let url = URL(filePath: path)
    guard let page = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        print("\(url.lastPathComponent): cannot read")
        continue
    }
    let started = Date()
    let analysis = try await cleaner.analyze(page)
    let analyzed = Date()
    let scanPage = ScanPage(quad: nil, analysis: analysis)
    let name = url.deletingPathExtension().lastPathComponent
    for look in [nil] + PageLook.allCases.map(Optional.some) {
        let image = cleaner.render(page, analysis: analysis, look: look ?? analysis.suggestedLook)
        if look == nil {
            let reading = Date()
            let document = try await processor.detectDocument(on: scanPage, flat: page, scanID: scan.id)
            let lines = store.text(of: scanPage, scanID: scan.id) ?? []
            print(String(format: "  text: %d lines, %d characters, %.0f ms", lines.count, lines.reduce(0) { $0 + $1.text.count }, Date().timeIntervalSince(reading) * 1000))
            let details = document.details
            print("  names: \(FileNamer.names(for: document.parts, date: .now))")
            print("  details: \(details.category.rawValue) · issuer \(details.issuer ?? "-") · date \(details.date.map(FileNamer.isoDate) ?? "-") · number \(details.number ?? "-") · keys \(document.issuerKeys)")
        }
        guard let data = extractor.jpegData(of: image, quality: 0.8) else { continue }
        try data.write(to: output.appending(path: "\(name)-\(look?.rawValue ?? "auto").jpg"))
    }
    let flat = store.flatURL(scanID: scan.id, page: scanPage)
    if (page.properties[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1 {
        try FileManager.default.copyItem(at: url, to: flat)
    } else if let data = extractor.jpegData(of: page, quality: 0.9) {
        try data.write(to: flat)
    }
    scan.pages.append(scanPage)
    print(String(format: "%@: %@, %@, skew %.2f°, color %.4f, picture %.3f, line %.4f, analysis %.0f ms", name, analysis.suggestedLook.rawValue, analysis.orientation.rawValue, analysis.skewDegrees, analysis.colorFraction, analysis.pictureFraction, analysis.textLineHeight ?? 0, analyzed.timeIntervalSince(started) * 1000))
}

let started = Date()
let data = try await processor.pdfData(of: scan)
try data.write(to: output.appending(path: "scan.pdf"))
print(String(format: "scan.pdf: %d pages, %d KB, %d KB per page, %.0f ms", scan.pages.count, data.count / 1024, data.count / 1024 / max(1, scan.pages.count), Date().timeIntervalSince(started) * 1000))

