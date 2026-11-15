import ScannerKit
import SwiftUI

struct PDFOptionsView: View {
    let scan: ScanModel
    @State private var sizes: [PDFQuality: Int] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(PDFQuality.allCases, id: \.self) { quality in
                        Button {
                            scan.setQuality(quality)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark").opacity(scan.quality == quality ? 1 : 0).foregroundStyle(.tint)
                                VStack(alignment: .leading) {
                                    Text(quality.title).fontWeight(.semibold)
                                    Text(quality.purpose).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let size = sizes[quality] {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).monospacedDigit().foregroundStyle(.secondary)
                                } else {
                                    ProgressView()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Size")
                } footer: {
                    Text("For this scan only; the default is in Settings.")
                }
            }
            .navigationTitle("PDF options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .task { sizes = await scan.pdfSizes() }
    }
}
