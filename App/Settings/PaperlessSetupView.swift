import ScannerKit
import ScannerModels
import SwiftUI

/// Connects an owner to a Paperless-ngx server: its address, an API token, and the storage path for the owner's documents.
struct PaperlessSetupView: View {
    @State private var setup: PaperlessSetup
    private let title: String
    private let ownerID: UUID
    private let settings: SettingsStore
    private let archiver: Archiver
    @State private var saveFailed = false
    @Environment(\.dismiss) private var dismiss

    init(ownerID: UUID, settings: SettingsStore, archiver: Archiver) {
        _setup = State(initialValue: PaperlessSetup(ownerID: ownerID, settings: settings, archiver: archiver, fetch: PaperlessHTTP.fetch))
        title = "Paperless for \(settings.value.owner(ownerID).name)"
        self.ownerID = ownerID
        self.settings = settings
        self.archiver = archiver
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $setup.address, prompt: Text("https://paperless.example.com"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API token", text: $setup.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("The token is in Paperless-ngx, under My Profile › API Auth Token. It stays in the Keychain of this iPhone.")
                }

                Section {
                    Button {
                        Task { await setup.connect() }
                    } label: {
                        HStack {
                            Text("Connect")
                            Spacer()
                            if setup.state == .connecting {
                                ProgressView()
                            } else if setup.isConnected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(setup.state == .connecting)
                } footer: {
                    if case .failed(let reason) = setup.state {
                        Text(reason).foregroundStyle(.red)
                    }
                }

                if case .connected(let paths) = setup.state {
                    Section {
                        Picker("Storage path", selection: $setup.storagePath) {
                            Text("Chosen by Paperless").tag(PaperlessStoragePath?.none)
                            ForEach(paths) { Text($0.name).tag(Optional($0)) }
                        }
                    } footer: {
                        Text("Where Paperless-ngx files these documents. Storage paths are made in Paperless-ngx, under Manage › Storage Paths.")
                    }
                }

                Section {
                    NavigationLink("What Archive Sends") { PaperlessGuideView(owner: settings.value.owner(ownerID)) }
                }

                if settings.value.owner(ownerID).paperless != nil {
                    Section {
                        Button("Disconnect", role: .destructive) {
                            PaperlessSetup.disconnect(ownerID, settings: settings, archiver: archiver)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                        .disabled(!setup.isConnected)
                }
            }
            .alert("The token could not be kept", isPresented: $saveFailed) {
                Button("OK") {}
            } message: {
                Text("The Keychain refused it. Try again.")
            }
        }
        .interactiveDismissDisabled(setup.hasChanges)
        .task { await setup.connectToSavedServer() }
    }

    private func save() {
        do {
            try setup.save()
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}
