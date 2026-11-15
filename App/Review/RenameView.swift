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
                    HStack(spacing: 2) {
                        TextField("File name", text: $name, selection: $selection)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(save)
                        Text(".pdf").foregroundStyle(.tertiary)
                    }
                } footer: {
                    Text("Used for the attached file and the email subject.")
                }
                if !suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                name = suggestion
                            } label: {
                                Label(suggestion, systemImage: suggestion.first?.isNumber == true ? "calendar" : "sparkles")
                            }
                        }
                    }
                }
            }
            .navigationTitle("File name")
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
                name = scan.scan.name
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
