import ScannerKit
import ScannerModels
import SwiftUI

struct DocumentTypesView: View {
    @Bindable var settings: SettingsStore
    @State private var newDocumentType = ""

    var body: some View {
        Form {
            Section {
                ForEach(settings.value.documentTypes.sorted(), id: \.self) { documentType in
                    Text(documentType.rawValue)
                }
                .onDelete { offsets in
                    let documentTypes = settings.value.documentTypes.sorted()
                    for index in offsets { settings.removeDocumentType(documentTypes[index]) }
                }
                TextField("New Document Type", text: $newDocumentType)
                    .submitLabel(.done)
                    .onSubmit {
                        settings.addDocumentType(newDocumentType)
                        newDocumentType = ""
                    }
            } header: {
                Text("Yours")
            } footer: {
                Text("Pick your document types in the details of a scan. The next document from the same issuer gets the same document type. The scans of an owner connected to Paperless offer the document types of its server instead.")
            }
            Section("Built-in") {
                ForEach(DocumentType.alphabetical(DocumentType.builtIn), id: \.self) { Text($0.rawValue) }
            }
        }
        .navigationTitle("Document Types")
        .navigationBarTitleDisplayMode(.inline)
    }
}
