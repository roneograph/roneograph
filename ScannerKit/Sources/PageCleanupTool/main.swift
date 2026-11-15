import CoreImage
import Foundation
import ScannerKit

// Usage: page-cleanup <output directory> <page images...>
// Writes the automatic result and every look of each page, and prints the analysis.
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
    var sizes: [String] = []
    for look in [nil] + PageLook.allCases.map(Optional.some) {
        let image = cleaner.render(page, analysis: analysis, settings: CleanupSettings(look: look))
        guard let data = extractor.jpegData(of: image, quality: 0.8) else { continue }
        try data.write(to: output.appending(path: "\(name)-\(look?.rawValue ?? "auto").jpg"))
        sizes.append("\(look?.rawValue ?? "auto") \(data.count / 1024) KB")
    }
    print(String(format: "%@: %@, %@, skew %.2f°, color %.4f, picture %.3f, analysis %.0f ms · %@", name, analysis.suggestedLook.rawValue, analysis.orientation.rawValue, analysis.skewDegrees, analysis.colorFraction, analysis.pictureFraction, analyzed.timeIntervalSince(started) * 1000, sizes.joined(separator: ", ")))
}
