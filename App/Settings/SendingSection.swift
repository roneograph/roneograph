import ScannerKit
import ScannerModels
import SwiftUI

/// How an owner's documents go out, in the order of the send bar; on the owner's page, and in the sheet the send bar opens when it has nothing to send with.
struct SendingSection: View {
    let app: AppModel
    let ownerID: UUID
    let title: String
    @State private var settingUpPaperless = false
    @State private var choosingFolder = false
    @State private var folderFailed = false
    @State private var folderMessage = ""

    private var settings: SettingsStore { app.settings }
    private var owner: Binding<Owner> { settings.binding(for: ownerID) }

    var body: some View {
        let current = owner.wrappedValue
        Section {
            if let archiver = app.archiver {
                Button { settingUpPaperless = true } label: {
                    LabeledContent {
                        if current.paperless == nil { Text("Connect…") }
                    } label: {
                        label(.paperless, subtitle: current.paperless?.summary)
                    }
                }
                .sheet(isPresented: $settingUpPaperless) { PaperlessSetupView(ownerID: ownerID, settings: settings, archiver: archiver) }
            }

            LabeledContent {
                EmailField(title: SendMethod.email.title, email: owner.email)
                    .multilineTextAlignment(.trailing)
            } label: {
                label(.email)
            }

            Toggle(isOn: owner.showsSaveToFiles) { label(.files) }
            if current.showsSaveToFiles {
                folder(current.archiveFolder)
            }

            Toggle(isOn: owner.showsShare) { label(.share) }
        } header: {
            Text(title)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let archiver = app.archiver, current.paperless != nil, !archiver.isConnected(current) {
                    Text("The Paperless token is no longer on this iPhone. Tap the server to connect again.").foregroundStyle(.red)
                }
                if !current.email.isEmpty, !current.hasValidEmail {
                    Text("This is not a valid email address.").foregroundStyle(.red)
                }
                Text("Ways in green send in a single tap. The send bar shows Archive and Email once they are set, Save to Files and Share when turned on.")
            }
        }
    }

    private func label(_ method: SendMethod, subtitle: String? = nil) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(method == .paperless ? "Archive to Paperless" : method.title)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        } icon: {
            SendingTile(method: method, isSet: app.isSet(method, for: owner.wrappedValue))
        }
    }

    /// Choosing the folder once a folder is set is a menu, so it can be forgotten.
    @ViewBuilder
    private func folder(_ folder: ArchiveFolder?) -> some View {
        Group {
            if let folder {
                Menu {
                    Button("Choose Another Folder…", systemImage: "folder") { choosingFolder = true }
                    Button("Forget Folder", systemImage: "folder.badge.minus", role: .destructive) { owner.wrappedValue.archiveFolder = nil }
                } label: {
                    LabeledContent("Folder", value: folder.name).foregroundStyle(.primary)
                }
            } else {
                Button { choosingFolder = true } label: {
                    LabeledContent("Folder", value: "Choose…").foregroundStyle(.primary)
                }
            }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try settings.chooseArchiveFolder(url, for: ownerID)
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
    }
}

/// A way to send in a rounded tile: in the accent color when it sends in a single tap, gray otherwise.
struct SendingTile: View {
    let method: SendMethod
    let isSet: Bool
    @ScaledMetric(relativeTo: .body) private var size = 29

    var body: some View {
        Image(systemName: method.systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(isSet ? Color.accentColor : Color(.systemGray), in: .rect(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

extension SendMethod {
    var systemImage: String {
        switch self {
        case .paperless: "archivebox"
        case .email: "envelope"
        case .files: "folder"
        case .share: "square.and.arrow.up"
        }
    }
}

extension PaperlessServer {
    /// "paperless.example.com · Inbox"
    var summary: String {
        [url.host() ?? url.absoluteString, storagePath?.name ?? "Chosen by Paperless"].joined(separator: " · ")
    }
}
