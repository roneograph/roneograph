import CoreImage
import Foundation
import ScannerKit

// Usage: page-cleanup <output directory> <page images...>
// Writes the automatic result and every look of each page, prints the analysis,
// then writes scan.pdf with all pages in their automatic look.
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
let writer = PDFWriter(context: context)
var pdfPages: [PDFPageContent] = []

for path in arguments.dropFirst() {
    let url = URL(filePath: path)
    guard let page = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        print("\(url.lastPathComponent): cannot read")
        continue
    }
    let started = Date()
    let analysis = try await cleaner.analyze(page)
    let analyzed = Date()
    let name = url.deletingPathExtension().lastPathComponent
    for look in [nil] + PageLook.allCases.map(Optional.some) {
        let image = cleaner.render(page, analysis: analysis, look: look ?? analysis.suggestedLook)
        if look == nil {
            let reading = Date()
            let lines = try await TextReader().lines(in: image)
            print(String(format: "  text: %d lines, %d characters, %.0f ms", lines.count, lines.reduce(0) { $0 + $1.text.count }, Date().timeIntervalSince(reading) * 1000))
            pdfPages.append(PDFPageContent(image: image, look: analysis.suggestedLook, textLineHeight: analysis.textLineHeight, text: lines))
            let document = DocumentDetector().detect(lines: lines, aspectRatio: image.extent.width / image.extent.height)
            let details = document.details
            print("  names: \(FileNamer.names(for: document.parts, date: .now))")
            print("  details: \(details.category.rawValue) · issuer \(details.issuer ?? "-") · date \(details.date.map(FileNamer.isoDate) ?? "-") · number \(details.number ?? "-") · keys \(document.issuerKeys)")
        }
        guard let data = extractor.jpegData(of: image, quality: 0.8) else { continue }
        try data.write(to: output.appending(path: "\(name)-\(look?.rawValue ?? "auto").jpg"))
    }
    print(String(format: "%@: %@, %@, skew %.2f°, color %.4f, picture %.3f, line %.4f, analysis %.0f ms", name, analysis.suggestedLook.rawValue, analysis.orientation.rawValue, analysis.skewDegrees, analysis.colorFraction, analysis.pictureFraction, analysis.textLineHeight ?? 0, analyzed.timeIntervalSince(started) * 1000))
}

let started = Date()
let data = try writer.data(pages: pdfPages, title: "Scan", defaultPaper: .a4)
try data.write(to: output.appending(path: "scan.pdf"))
print(String(format: "scan.pdf: %d pages, %d KB, %d KB per page, %.0f ms", pdfPages.count, data.count / 1024, data.count / 1024 / max(1, pdfPages.count), Date().timeIntervalSince(started) * 1000))
