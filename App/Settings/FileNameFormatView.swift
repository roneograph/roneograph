import ScannerKit
import ScannerModels
import SwiftUI

/// Edits the custom file name format; only a valid format replaces the one in use.
struct FileNameFormatView: View {
    @Binding var format: FileNameFormat
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        Form {
            Section {
                TextField("Format", text: $draft, axis: .vertical)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($isEditing)
                if let error {
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    FileNameParts(segments: format.sampleSegments + [FileNameSegment(".pdf", .text)])
                        .padding(.vertical, 4)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("For a made-up invoice from Lumen Energy.")
                    Text("Each / starts a folder; Share and Paperless get the file name only.")
                    Text("A variable with no value disappears, with the separator next to it.")
                    Text("{NAME} leaves out of a suggested name what the format already shows; a name you type stays whole.")
                }
            }
            Section("Variables") {
                ForEach(FileNameFormat.Template.Variable.allCases, id: \.self) { variable in
                    Button {
                        draft += variable.placeholder
                    } label: {
                        LabeledContent {
                            Text(sampleValue(of: variable).map { "\(variable.explanation) · \($0)" } ?? variable.explanation)
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
            if value.contains(where: \.isNewline) {
                draft = value.filter { !$0.isNewline }
                isEditing = false
            } else if (try? FileNameFormat.Template(value)) != nil { format.template = value }
        }
    }

    /// What the variable alone gives for the made-up invoice, with the separator and case of the format; nil for the name, which depends on the rest of the format.
    private func sampleValue(of variable: FileNameFormat.Template.Variable) -> String? {
        guard variable != .name else { return nil }
        var alone = format
        alone.isCustom = true
        alone.template = variable.placeholder
        return alone.sampleFileName
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
        case .year, .shortYear: "Year"
        case .month: "Month"
        case .day: "Day"
        case .category: "Category"
        case .issuer: "Issuer"
        case .number: "Reference number"
        }
    }
}

/// A made-up invoice, to show what file name formats and Paperless storage paths give.
enum SampleDocument {
    static let name = "Invoice Lumen Energy"
    static let category = DocumentCategory.invoice
    static let issuer = "Lumen Energy"
    static let number = "2026-0042"
}

extension FileNameFormat {
    var sampleSegments: [FileNameSegment] {
        segments(
            name: SampleDocument.name,
            details: DocumentDetails(category: SampleDocument.category, issuer: SampleDocument.issuer, date: .now, number: SampleDocument.number),
            scanDate: .now,
            suggestedParts: SuggestedParts(type: SampleDocument.category.rawValue, issuer: SampleDocument.issuer, number: SampleDocument.number)
        )
    }

    var sampleFileName: String {
        sampleSegments.map(\.text).joined()
    }
}
