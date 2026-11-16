import ScannerKit
import ScannerModels
import SwiftUI

/// The owners, to open one or add another, and which one documents go to when nothing tells.
struct OwnersSection: View {
    let app: AppModel
    @Bindable var settings: SettingsStore
    @State private var adding = false
    @State private var newName = ""

    var body: some View {
        Section {
            ForEach(settings.value.owners) { owner in
                NavigationLink {
                    OwnerView(app: app, settings: settings, ownerID: owner.id)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(owner.name)
                            if let destinations = destinations(of: owner) {
                                Text(destinations).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    } icon: {
                        Image(systemName: owner.symbol.systemImage).foregroundStyle(.tint)
                    }
                }
            }
            Button("Add Owner…", systemImage: "plus") { adding = true }
            if settings.value.hasSeveralOwners {
                Picker("Default owner", selection: $settings.value.defaultOwnerID) {
                    ForEach(settings.value.owners) { Text($0.name).tag($0.id) }
                }
            }
        } header: {
            Text("Owners")
        } footer: {
            Text(settings.value.hasSeveralOwners
                ? "Each document goes to its owner's email address and folder, named with its format. The owner is read from the page or remembered per issuer; otherwise it is the default owner."
                : "Add an owner for a company you scan for: its documents get their own email address, folder and file names.")
        }
        .alert("New Owner", isPresented: $adding) {
            TextField("Name", text: $newName)
            Button("Add") {
                settings.addOwner(newName)
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("A company you scan documents for, such as your employer.")
        }
    }

    private func destinations(of owner: Owner) -> String? {
        let parts = [owner.hasValidEmail ? owner.email : nil, owner.archiveFolder?.name].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One owner: its name, where its PDFs go, how they are named and how its documents are recognized.
struct OwnerView: View {
    let app: AppModel
    @Bindable var settings: SettingsStore
    let ownerID: UUID
    @State private var deleting = false
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    private var owner: Binding<Owner> { settings.binding(for: ownerID) }
    private var isDefault: Bool { ownerID == settings.value.defaultOwnerID }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .onSubmit(rename)
                Picker("Symbol", selection: owner.symbol) {
                    ForEach(Owner.Symbol.allCases, id: \.self) { symbol in
                        Image(systemName: symbol.systemImage).tag(symbol)
                    }
                }
                .pickerStyle(.segmented)
            }

            OwnerSections(settings: settings, owner: owner, includesCustomFormat: true)

            if settings.value.hasSeveralOwners {
                Section {
                    LabeledContent("Its lines on the page", value: settings.recognizesLines(of: ownerID) ? "Recognized" : "Not yet")
                    LabeledContent("Issuers remembered", value: "\(settings.issuerCount(of: ownerID))")
                } header: {
                    Text("Recognized by")
                } footer: {
                    Text("A line that only shows on this owner's documents, such as its name, gives it the next documents once they are sent. Only fingerprints of the lines are kept.")
                }
            }

            Section {
                if isDefault {
                    Text("The default owner gets the documents nothing tells the owner of.").foregroundStyle(.secondary)
                } else {
                    Button("Make Default Owner") { settings.value.defaultOwnerID = ownerID }
                    Button("Delete Owner…", role: .destructive) { deleting = true }
                }
            }
        }
        .navigationTitle(owner.wrappedValue.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = owner.wrappedValue.name }
        .onDisappear(perform: rename)
        .confirmationDialog("Delete \(owner.wrappedValue.name)?", isPresented: $deleting, titleVisibility: .visible) {
            let scans = app.scans(of: ownerID)
            if scans.isEmpty {
                Button("Delete Owner", role: .destructive) { delete(movingScansTo: nil) }
            } else {
                ForEach(settings.value.owners.filter { $0.id != ownerID }) { other in
                    Button("Move Scans to \(other.name)") { delete(movingScansTo: other.id) }
                }
                Button("Delete \(scans.count == 1 ? "Its Scan" : "Its \(scans.count) Scans")", role: .destructive) { delete(movingScansTo: nil) }
            }
        } message: {
            let count = app.scans(of: ownerID).count
            Text(count == 0
                ? "Its email address, folder and file name format are forgotten."
                : "\(count.counted("scan")) on this iPhone belong to it: move them to another owner, or delete them. PDFs already sent or saved stay where they are.")
        }
    }

    /// An empty name or another owner's puts the name back.
    private func rename() {
        if !settings.renameOwner(ownerID, to: name) { name = owner.wrappedValue.name }
    }

    private func delete(movingScansTo newOwner: UUID?) {
        dismiss()
        app.deleteOwner(ownerID, movingScansTo: newOwner)
    }
}
