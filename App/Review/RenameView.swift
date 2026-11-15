import ScannerKit
import SwiftUI

struct RenameView: View {
    let scan: ScanModel
    @State private var name = ""
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    private let namer = FileNamer()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, selection: $selection)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    Text("File: \(scan.fileName(for: name.isEmpty ? scan.scan.suggestions.first ?? scan.fallbackTitle : name)).pdf\nThe name is the email subject; the file name follows the format in Settings.")
                }
                if !suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                name = suggestion
                            } label: {
                                Label(suggestion, systemImage: "sparkles")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", action: save)
                }
            }
            .onChange(of: name) { _, value in
                let sanitized = namer.sanitize(value)
                if sanitized != value { name = sanitized }
            }
            .onAppear {
                name = scan.scan.title
                selection = TextSelection(range: name.startIndex..<name.endIndex)
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var suggestions: [String] {
        scan.scan.suggestions.filter { $0 != name }
    }

    private func save() {
        scan.rename(name)
        dismiss()
    }
}
