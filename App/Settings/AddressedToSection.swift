import ScannerKit
import ScannerModels
import SwiftUI

/// The names and addresses an owner's mail is sent to, which give it the documents showing one of them.
struct AddressedToSection: View {
    @Bindable var settings: SettingsStore
    let ownerID: UUID
    @State private var editing: Entry?

    /// A name or an address being added, or edited at its index.
    private struct Entry: Identifiable {
        enum Kind { case name, address }
        var kind: Kind
        var index: Int?
        var text = ""

        var id: String { "\(kind)-\(index ?? -1)" }
    }

    private var owner: Owner { settings.value.owner(ownerID) }

    var body: some View {
        Section {
            if !owner.hasPlaceholderName {
                LabeledContent {
                    Text("Name")
                } label: {
                    Text(owner.name).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(owner.names.enumerated()), id: \.offset) { index, name in
                Button(name) { editing = Entry(kind: .name, index: index, text: name) }
                    .foregroundStyle(.primary)
            }
            .onDelete { remove(\.names, at: $0) }
            Button("Add Name…", systemImage: "plus") { editing = Entry(kind: .name) }
            ForEach(Array(owner.addresses.enumerated()), id: \.offset) { index, address in
                Button { editing = Entry(kind: .address, index: index, text: address) } label: {
                    Text(address).multilineTextAlignment(.leading)
                }
                .foregroundStyle(.primary)
            }
            .onDelete { remove(\.addresses, at: $0) }
            Button("Add Address…", systemImage: "plus") { editing = Entry(kind: .address) }
                .sheet(item: $editing) { entry in
                    EntryEditor(entry: entry) { text in
                        switch entry.kind {
                        case .name: settings.setName(text, at: entry.index, of: ownerID)
                        case .address: settings.setAddress(text, at: entry.index, of: ownerID)
                        }
                    }
                }
        } header: {
            Text("Addressed To")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(settings.value.addressedToFooter(of: ownerID, region: Locale.current.region?.identifier, language: Locale.current.language.languageCode?.identifier))
                if let warning = settings.value.sharedAddressWarning(of: ownerID) {
                    Text(warning).foregroundStyle(Color(.warning))
                }
            }
        }
    }

    private func remove(_ list: WritableKeyPath<Owner, [String]>, at offsets: IndexSet) {
        var owner = owner
        owner[keyPath: list].remove(atOffsets: offsets)
        settings.value.updateOwner(owner)
    }

    /// One name on a line, or one address on as many lines as printed.
    private struct EntryEditor: View {
        let entry: Entry
        let done: (String) -> Void
        @State private var text = ""
        @FocusState private var isFocused: Bool
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        switch entry.kind {
                        case .name:
                            TextField("Name", text: $text)
                                .textContentType(.name)
                                .submitLabel(.done)
                                .onSubmit(save)
                                .focused($isFocused)
                        case .address:
                            TextField("Address", text: $text, axis: .vertical)
                                .lineLimit(3...8)
                                .textContentType(.fullStreetAddress)
                                .focused($isFocused)
                        }
                    } footer: {
                        Text(entry.kind == .name
                            ? "Another name its mail is addressed to, such as a maiden name or a brand."
                            : "As it is printed on the mail: the street and the postcode with the town are enough.")
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: save)
                            .disabled(entry.index == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear {
                    text = entry.text
                    isFocused = true
                }
            }
            .presentationDetents([.medium, .large])
        }

        private var title: String {
            switch entry.kind {
            case .name: entry.index == nil ? "New Name" : "Name"
            case .address: entry.index == nil ? "New Address" : "Address"
            }
        }

        private func save() {
            done(text)
            dismiss()
        }
    }
}
