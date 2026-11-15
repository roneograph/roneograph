import CoreImage
import Foundation
import ScannerKit

// Usage: page-cleanup <output directory> <page images...>
// Writes the automatic result and every look of each page, prints the analysis,
// then writes scan-<quality>.pdf with all pages in their automatic look.
let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("Usage: page-cleanup <output directory> <page images...>\n".utf8))
    exit(1)
}
let output = URL(filePath: arguments.first!)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let context = CIContext()
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
    let analysis = cleaner.analyze(page)
    let analyzed = Date()
    let name = url.deletingPathExtension().lastPathComponent
    for look in [nil] + PageLook.allCases.map(Optional.some) {
        let image = cleaner.render(page, analysis: analysis, settings: CleanupSettings(look: look))
        if look == nil { pdfPages.append(PDFPageContent(image: image, look: analysis.suggestedLook)) }
        guard let data = extractor.jpegData(of: image, quality: 0.8) else { continue }
        try data.write(to: output.appending(path: "\(name)-\(look?.rawValue ?? "auto").jpg"))
    }
    print(String(format: "%@: %@, %@, skew %.2f°, color %.4f, picture %.3f, analysis %.0f ms", name, analysis.suggestedLook.rawValue, analysis.orientation.rawValue, analysis.skewDegrees, analysis.colorFraction, analysis.pictureFraction, analyzed.timeIntervalSince(started) * 1000))
}

for quality in PDFQuality.allCases {
    for (suffix, pages) in [("", pdfPages), ("-bw", pdfPages.map { PDFPageContent(image: $0.image, look: .blackAndWhite) })] {
        let started = Date()
        let data = try writer.data(pages: pages, title: "Scan", quality: quality, defaultPaper: .a4)
        try data.write(to: output.appending(path: "scan-\(quality.rawValue)\(suffix).pdf"))
        print(String(format: "scan-%@%@.pdf: %d pages, %d KB, %d KB per page, %.0f ms", quality.rawValue, suffix, pages.count, data.count / 1024, data.count / 1024 / max(1, pages.count), Date().timeIntervalSince(started) * 1000))
    }
}
