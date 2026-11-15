import CoreImage
import ScannerKit
import SwiftUI

/// Builds the session's PDF in each quality, to compare sizes and share one.
struct PDFExportView: View {
    let pages: [SpikePage]
    let directory: URL
    let exporter: PDFExporter
    @State private var quality = PDFQuality.balanced
    @State private var files: [PDFQuality: URL] = [:]
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                Picker("Size", selection: $quality) {
                    ForEach(PDFQuality.allCases, id: \.self) { quality in
                        HStack {
                            Text(quality.rawValue.capitalized)
                            Spacer()
                            if let size = files[quality].flatMap(Self.size) { Text(size).foregroundStyle(.secondary) } else { ProgressView() }
                        }
                        .tag(quality)
                    }
                }
                .pickerStyle(.inline)
            }
            .navigationTitle("PDF · \(pages.count) pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    if let url = files[quality] {
                        ShareLink(item: url) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .alert("Cannot write the PDF", isPresented: $failed) {}
        }
        .task {
            for quality in [PDFQuality.balanced, .small, .best] {
                let url = directory.appending(path: "scan-\(quality.rawValue).pdf")
                do {
                    try await exporter.write(pages: pages, quality: quality, to: url)
                    files[quality] = url
                } catch {
                    failed = true
                }
            }
        }
    }

    private static func size(of url: URL) -> String? {
        guard let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct PDFExporter: Sendable {
    let cleaner: PageCleaner
    let writer: PDFWriter

    func write(pages: [SpikePage], quality: PDFQuality, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let contents = pages.compactMap { page -> PDFPageContent? in
                guard let flat = CIImage(contentsOf: page.pageURL) else { return nil }
                let analysis = page.metadata.analysis
                return PDFPageContent(image: cleaner.render(flat, analysis: analysis), look: analysis.suggestedLook)
            }
            try writer.data(pages: contents, title: "Scan", quality: quality, defaultPaper: .a4).write(to: url)
        }.value
    }
}
