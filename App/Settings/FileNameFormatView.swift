import ScannerKit
import ScannerModels
import SwiftUI

/// Edits the custom file name format; only a valid format replaces the one in use.
struct FileNameFormatView: View {
    @Binding var format: FileNameFormat
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                TextField("Format", text: $draft, axis: .vertical)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if let error {
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    Label("\(format.sampleFileName).pdf", systemImage: "doc")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Use / to file scans into folders inside the Save to Files folder; Email and Share only use the file name. An empty value disappears with the separator next to it.")
            }
            Section("Variables") {
                ForEach(FileNameFormat.Template.Variable.allCases, id: \.self) { variable in
                    Button {
                        draft += variable.placeholder
                    } label: {
                        LabeledContent {
                            Text(variable.explanation)
                        } label: {
                            Text(variable.placeholder).font(.body.monospaced())
                        }
                    }
                }
            }
            Section {
                Button("Reset Format") { draft = FileNameFormat.defaultTemplate }
            }
        }
        .navigationTitle("Format")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = format.template }
        .onChange(of: draft) { _, value in
            if (try? FileNameFormat.Template(value)) != nil { format.template = value }
        }
    }

    private var error: FileNameFormat.Template.ParseError? {
        do {
            _ = try FileNameFormat.Template(draft)
            return nil
        } catch {
            return error
        }
    }
}

extension FileNameFormat.Template.Variable {
    var explanation: String {
        switch self {
        case .name: "Name, without what the format shows"
        case .year: "Year, 2026"
        case .shortYear: "Year, 26"
        case .month: "Month, 11"
        case .day: "Day, 12"
        case .category: "Category"
        case .issuer: "Issuer"
        case .number: "Reference number"
        }
    }
}

extension FileNameFormat {
    /// The file name of a made-up invoice, to show the format.
    var sampleFileName: String {
        fileName(
            name: "Invoice Lumen Energy",
            details: DocumentDetails(category: .invoice, issuer: "Lumen Energy", date: .now, number: "2026-0042"),
            scanDate: .now,
            suggestedParts: SuggestedParts(type: "Invoice", issuer: "Lumen Energy", number: "2026-0042")
        )
    }
}
