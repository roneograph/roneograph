import ScannerKit
import ScannerModels
import SwiftUI

/// The owners, each with the ways its documents go out, to open one or add another; the same with one owner or several.
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
                    OwnerRow(app: app, owner: owner, isDefault: owner.id == settings.value.defaultOwnerID)
                }
            }
            Button("Add Owner…", systemImage: "plus") { adding = true }
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
        } header: {
            Text("Owners")
        } footer: {
            Text("Add an owner for a company you scan for: its documents get their own ways to send and file names. The owner of a document is read from the page or remembered per issuer; otherwise it is the default owner.")
        }
    }
}

/// An owner, and in the accent color the ways that send its documents in a single tap.
private struct OwnerRow: View {
    let app: AppModel
    let owner: Owner
    let isDefault: Bool
    @ScaledMetric(relativeTo: .body) private var size = 32

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: owner.symbol.badgeImage)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: size, height: size)
                .background(Color.accentColor.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(owner.name)
                if isDefault {
                    Text("Default").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                ForEach(SendMethod.inBarOrder, id: \.self) { method in
                    Image(systemName: method.systemImage)
                        .foregroundStyle(app.isSet(method, for: owner) ? Color.accentColor : Color(.systemGray3))
                }
            }
            .font(.footnote)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.summary(of: owner))
    }
}

/// One owner: its name, how its PDFs go out, how they are named and how its documents are recognized.
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
                        Image(systemName: symbol.systemImage).accessibilityLabel(symbol.name).tag(symbol)
                    }
                }
                .pickerStyle(.segmented)
            }

            SendingSection(app: app, ownerID: ownerID, title: "Sending")
            FileNameSection(owner: owner)

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

extension SettingsStore {
    /// An owner as a binding, for the views that edit it.
    func binding(for ownerID: UUID) -> Binding<Owner> {
        Binding(get: { self.value.owner(ownerID) }, set: { self.value.updateOwner($0) })
    }
}

extension Owner.Symbol {
    var systemImage: String {
        switch self {
        case .person: "person.crop.circle"
        case .house: "house"
        case .building: "building.2"
        case .briefcase: "briefcase"
        }
    }

    /// The symbol drawn in a circle.
    var badgeImage: String {
        self == .person ? "person" : systemImage
    }

    var name: String {
        switch self {
        case .person: "Person"
        case .house: "House"
        case .building: "Building"
        case .briefcase: "Briefcase"
        }
    }
}
