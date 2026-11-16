import ScannerKit
import ScannerModels
import SwiftUI

struct CategoriesView: View {
    @Bindable var settings: SettingsStore
    @State private var newCategory = ""

    var body: some View {
        Form {
            Section {
                ForEach(settings.value.categories.sorted(), id: \.self) { category in
                    Text(category.rawValue)
                }
                .onDelete { offsets in
                    let categories = settings.value.categories.sorted()
                    for index in offsets { settings.removeCategory(categories[index]) }
                }
                TextField("New Category", text: $newCategory)
                    .submitLabel(.done)
                    .onSubmit {
                        settings.addCategory(newCategory)
                        newCategory = ""
                    }
            } header: {
                Text("Yours")
            } footer: {
                Text("Pick your categories in the details of a scan. The next document from the same issuer gets the same category.")
            }
            Section("Built-in") {
                ForEach(DocumentCategory.builtIn, id: \.self) { Text($0.rawValue) }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
    }
}
