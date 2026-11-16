import ScannerKit
import ScannerModels
import SwiftUI

/// The name of a scan and the details of its document.
struct RenameView: View {
    let scan: ScanModel
    @Bindable var settings: SettingsStore
    @State private var name = ""
    @State private var details = DocumentDetails()
    /// The name and details when the sheet opened or when the text was read, to keep what arrives while the user has not touched them.
    @State private var shownName = ""
    @State private var shownDetails = DocumentDetails()
    @State private var selection: TextSelection?
    @State private var addingCategory = false
    @State private var newCategory = ""
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
                    Label("\(scan.fileName(for: name.isEmpty ? scan.scan.suggestions.first ?? scan.fallbackTitle : name, details: details)).pdf", systemImage: "doc")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("The name is the email subject; the file name follows the format in Settings.")
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
                Section {
                    LabeledContent("Category") {
                        Menu {
                            Picker("Category", selection: $details.category) {
                                ForEach(categories, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            Button("New Category…", systemImage: "plus") { addingCategory = true }
                        } label: {
                            Text(details.category.rawValue)
                        }
                    }
                    LabeledContent("Issuer") {
                        TextField("None", text: text(\.issuer))
                            .textContentType(.organizationName)
                            .multilineTextAlignment(.trailing)
                    }
                    if let date = details.date {
                        HStack {
                            DatePicker("Date", selection: Binding(get: { date }, set: { details.date = $0 }), displayedComponents: .date)
                            Button("Clear Date", systemImage: "xmark.circle.fill") { details.date = nil }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                                .buttonStyle(.plain)
                        }
                    } else {
                        Button("Add Date") { details.date = scan.scan.created }
                    }
                    LabeledContent("Number") {
                        TextField("None", text: text(\.number))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Details")
                } footer: {
                    Text("Read on the first page. A new issuer or category is reused for the next document from the same issuer.")
                }
            }
            .navigationTitle("Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", action: save)
                }
            }
            .alert("New Category", isPresented: $addingCategory) {
                TextField("Name", text: $newCategory)
                Button("Add") {
                    if let category = settings.addCategory(newCategory) { details.category = category }
                    newCategory = ""
                }
                Button("Cancel", role: .cancel) { newCategory = "" }
            }
            .onChange(of: name) { _, value in
                let sanitized = namer.sanitize(value)
                if sanitized != value { name = sanitized }
            }
            .onChange(of: scan.scan.title) { _, title in
                if name == shownName {
                    name = title
                    selection = TextSelection(range: name.startIndex..<name.endIndex)
                }
                shownName = title
            }
            .onChange(of: scan.scan.details) { _, read in
                if details == shownDetails { details = read }
                shownDetails = read
            }
            .onAppear {
                name = scan.scan.title
                shownName = name
                details = scan.scan.details
                shownDetails = details
                selection = TextSelection(range: name.startIndex..<name.endIndex)
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var suggestions: [String] {
        scan.scan.suggestions.filter { $0 != name }
    }

    /// The categories to pick from, with the current one even when the user removed it since.
    private var categories: [DocumentCategory] {
        let all = settings.value.allCategories
        return all.contains(details.category) ? all : all + [details.category]
    }

    /// An optional detail edited as text, empty meaning none.
    private func text(_ keyPath: WritableKeyPath<DocumentDetails, String?>) -> Binding<String> {
        Binding(
            get: { details[keyPath: keyPath] ?? "" },
            set: { details[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func save() {
        details.issuer = details.issuer?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        details.number = details.number?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        scan.applyEdits(name: name, details: details, shownName: shownName, shownDetails: shownDetails)
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
