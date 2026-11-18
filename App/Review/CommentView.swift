import ScannerModels
import SwiftUI

/// Edits what the page does not say, such as who was at a lunch; a blank comment removes it.
struct CommentView: View {
    let scan: ScanModel
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Comment", text: $text, prompt: Text("Who was there, what it was for…"), axis: .vertical)
                        .lineLimit(4...)
                        .focused($focused)
                        .textInputAutocapitalization(.sentences)
                } footer: {
                    Text("Written in the PDF and sent with it: as the text of the email, or in a Comment field on Paperless.")
                }
            }
            .navigationTitle("Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        scan.setComment(text)
                        dismiss()
                    }
                }
            }
            .onAppear {
                text = scan.scan.comment ?? ""
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(text != (scan.scan.comment ?? ""))
    }
}
