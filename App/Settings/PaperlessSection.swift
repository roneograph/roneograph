import ScannerKit
import ScannerModels
import SwiftUI

/// Where Archive sends an owner's documents, on the owner's page.
struct PaperlessSection: View {
    let app: AppModel
    let ownerID: UUID
    @State private var settingUpPaperless = false

    private var settings: SettingsStore { app.settings }

    var body: some View {
        let owner = settings.value.owner(ownerID)
        if let archiver = app.archiver {
            Section {
                Button { settingUpPaperless = true } label: {
                    LabeledContent {
                        if owner.paperless == nil { Text("Connect…") }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Archive to Paperless")
                                if let summary = owner.paperless?.summary {
                                    Text(summary).font(.footnote).foregroundStyle(Color.secondary)
                                }
                            }
                            .foregroundStyle(Color.primary)
                        } icon: {
                            SendingTile(method: .paperless, isSet: app.isConnected(owner))
                        }
                    }
                }
                .sheet(isPresented: $settingUpPaperless) { PaperlessSetupView(ownerID: ownerID, settings: settings, archiver: archiver) }
            } header: {
                Text("Paperless")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if owner.paperless != nil, !archiver.isConnected(owner) {
                        Text("The Paperless token is no longer on this iPhone. Tap Archive to Paperless to connect again.").foregroundStyle(.red)
                    }
                    Text("Archive sends this owner's scans here in one tap. Share is always there for anything else.")
                }
            }
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
