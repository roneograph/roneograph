import ScannerKit
import ScannerModels
import SwiftUI

/// Where an owner's PDFs go and how they are named: in Settings with one owner, in the owner's page with several.
struct OwnerSections: View {
    let settings: SettingsStore
    let archiver: Archiver?
    @Binding var owner: Owner
    /// With several owners, the custom format switch sits with the rest of the owner's file name.
    var includesCustomFormat = false
    /// The setting shared by all owners, shown with the file name when there is a single owner.
    var askForName: Binding<Bool>?
    @State private var choosingFolder = false
    @State private var folderFailed = false
    @State private var folderMessage = ""
    @State private var settingUpPaperless = false

    var body: some View {
        Section {
            EmailField(title: "Send to", email: $owner.email)
        } header: {
            Text("Email")
        } footer: {
            if !owner.email.isEmpty, !owner.hasValidEmail {
                Text("This is not a valid email address.").foregroundStyle(.red)
            } else {
                Text("Fills in the recipient of the Email button. Needs an account in the Mail app.")
            }
        }

        Section {
            Button { choosingFolder = true } label: {
                LabeledContent("Folder", value: owner.archiveFolder?.name ?? "Choose…")
            }
            if owner.archiveFolder != nil {
                Button("Forget Folder", role: .destructive) { owner.archiveFolder = nil }
            }
        } header: {
            Text("Save to Files")
        } footer: {
            Text("The Save button puts PDFs in this folder without asking each time.")
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try settings.chooseArchiveFolder(url, for: owner.id)
            } catch {
                folderMessage = (error as? SettingsStore.FolderError)?.localizedDescription ?? ""
                folderFailed = true
            }
        }
        .alert("This folder cannot be used", isPresented: $folderFailed) {
            Button("OK") {}
        } message: {
            if !folderMessage.isEmpty { Text(folderMessage) }
        }

        if let archiver {
            Section {
                if let server = owner.paperless {
                    Button { settingUpPaperless = true } label: {
                        LabeledContent("Server", value: server.url.host() ?? server.url.absoluteString)
                    }
                    .sheet(isPresented: $settingUpPaperless) { PaperlessSetupView(ownerID: owner.id, settings: settings, archiver: archiver) }
                    LabeledContent("Storage path", value: server.storagePath?.name ?? "Chosen by Paperless")
                    Button("Disconnect", role: .destructive) { PaperlessSetup.disconnect(owner.id, settings: settings, archiver: archiver) }
                } else {
                    Button("Connect…") { settingUpPaperless = true }
                        .sheet(isPresented: $settingUpPaperless) { PaperlessSetupView(ownerID: owner.id, settings: settings, archiver: archiver) }
                }
            } header: {
                Text("Paperless")
            } footer: {
                if owner.paperless != nil, !archiver.isConnected(owner) {
                    Text("The token is no longer on this iPhone. Tap the server to connect again.").foregroundStyle(.red)
                } else {
                    Text("The Archive button sends PDFs to this Paperless-ngx server, with their title, date and category as document type, which is created when missing.")
                }
            }
        }

        Section {
            Label("\(owner.fileNameFormat.sampleFileName).pdf", systemImage: "doc")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if includesCustomFormat {
                Toggle("Custom format", isOn: $owner.fileNameFormat.isCustom)
            }
            if owner.fileNameFormat.isCustom {
                NavigationLink {
                    FileNameFormatView(format: $owner.fileNameFormat)
                } label: {
                    LabeledContent("Format", value: owner.fileNameFormat.template)
                }
            } else {
                Picker("Date", selection: $owner.fileNameFormat.datePosition) {
                    Text("None").tag(FileNameFormat.DatePosition.none)
                    Text("First").tag(FileNameFormat.DatePosition.start)
                    Text("Last").tag(FileNameFormat.DatePosition.end)
                }
                if owner.fileNameFormat.datePosition != .none {
                    Picker("Date format", selection: $owner.fileNameFormat.dateStyle) {
                        ForEach(FileNameFormat.DateStyle.allCases, id: \.self) { Text($0.format(.now)).tag($0) }
                    }
                }
            }
            if owner.fileNameFormat.isCustom || owner.fileNameFormat.datePosition != .none {
                Picker("Date of", selection: $owner.fileNameFormat.dateSource) {
                    Text("The document").tag(FileNameFormat.DateSource.document)
                    Text("The scan").tag(FileNameFormat.DateSource.scan)
                }
            }
            Picker("Separator", selection: $owner.fileNameFormat.separator) {
                Text("a b").tag(FileNameFormat.Separator.space)
                Text("a-b").tag(FileNameFormat.Separator.dash)
                Text("a_b").tag(FileNameFormat.Separator.underscore)
            }
            .pickerStyle(.segmented)
            Toggle("Lowercase", isOn: $owner.fileNameFormat.lowercase)
            if let askForName {
                Toggle("Ask for a name", isOn: askForName)
            }
        } header: {
            Text("File name")
        } footer: {
            if includesCustomFormat {
                Text("A custom format builds file names from the details of the document, such as {YYYY}-{MM} {ISSUER}, and can file scans into folders.")
            } else {
                Text("The name is found in the text, and a name you correct is reused for the next documents from the same issuer, with their own date and number where yours had them. The date of the document is the one printed on it, or the day of the scan when there is none.")
            }
        }
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

    var name: String {
        switch self {
        case .person: "Person"
        case .house: "House"
        case .building: "Building"
        case .briefcase: "Briefcase"
        }
    }
}
