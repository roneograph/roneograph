import ScannerKit
import ScannerModels
import SwiftUI

struct SettingsView: View {
    let app: AppModel
    @Bindable var settings: SettingsStore
    @State private var forgettingEverything = false
    @State private var deletingScans = false
    @State private var storedBytes = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if settings.value.hasSeveralOwners {
                    OwnersSection(app: app, settings: settings)
                    Section {
                        Toggle("Ask for a name", isOn: $settings.value.askForName)
                    } footer: {
                        Text("The name is found in the text, and a name you correct is reused for the next documents from the same issuer, with their own date and number where yours had them.")
                    }
                } else {
                    OwnerSections(settings: settings, owner: $settings.value.defaultOwner, askForName: $settings.value.askForName)
                }

                Section {
                    if !settings.value.hasSeveralOwners {
                        Toggle("Custom format", isOn: $settings.value.defaultOwner.fileNameFormat.isCustom)
                    }
                    NavigationLink("Categories") { CategoriesView(settings: settings) }
                    if !settings.value.hasSeveralOwners {
                        NavigationLink(value: Screen.owners) {
                            LabeledContent("Owners", value: "\(settings.value.owners.count)")
                        }
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    if !settings.value.hasSeveralOwners {
                        Text("A custom format builds file names from the details of the document, such as {YYYY}-{MM} {ISSUER}, and can file scans into folders.")
                    }
                }

                Section {
                    NavigationLink {
                        IssuersView(settings: settings)
                    } label: {
                        LabeledContent {
                            Text("\(settings.value.learnedIssuers.count)")
                        } label: {
                            Label { Text("Issuers") } icon: { RememberedMark().accessibilityHidden(true) }
                        }
                    }
                    LabeledContent {
                        Text(settings.recognizesOwnLines ? "Recognized" : "Not yet")
                    } label: {
                        Label("Your name and address", systemImage: "person.crop.circle")
                    }
                    Button("Forget Everything…", role: .destructive) { forgettingEverything = true }
                        .disabled(!settings.hasLearned)
                } header: {
                    Text("Memory")
                } footer: {
                    Text("Corrections are reused for the next documents from the same issuer. Your name and address are recognized so they are never taken as the issuer; only fingerprints of these lines are kept. Nothing leaves this iPhone.")
                }
                .confirmationDialog("Forget everything Roneograph remembers?", isPresented: $forgettingEverything, titleVisibility: .visible) {
                    Button("Forget Everything", role: .destructive) { settings.forgetEverything() }
                } message: {
                    Text(settings.value.forgetEverythingMessage)
                }

                Section {
                    Picker("Keep scans for", selection: $settings.value.keepScans) {
                        ForEach(ScanRetention.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    LabeledContent("Stored", value: stored)
                    Button("Delete All Scans…", role: .destructive) { deletingScans = true }
                        .disabled(app.scans.isEmpty)
                } header: {
                    Text("Scans on this iPhone")
                } footer: {
                    Text(settings.value.keepScans == .forever
                        ? "Scans stay until you delete them. PDFs saved with Save to Files or sent stay where they are."
                        : "Scans are deleted after this time, sent or not. PDFs saved with Save to Files or sent stay where they are.")
                }
                .confirmationDialog("Delete \(app.scans.count == 1 ? "the scan" : "all \(app.scans.count) scans")?", isPresented: $deletingScans, titleVisibility: .visible) {
                    Button("Delete All Scans", role: .destructive) {
                        app.deleteAllScans()
                        Task { storedBytes = await app.store.byteCount() }
                    }
                } message: {
                    Text("Their pages and PDFs are deleted from this iPhone. PDFs saved with Save to Files or sent are not affected.")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        LabeledContent {
                            Text(AppVersion.marketing)
                        } label: {
                            HStack(spacing: 12) {
                                AppIcon(size: 30).accessibilityHidden(true)
                                Text("About Roneograph")
                            }
                        }
                    }
                }
            }
            // Pushed by value, so adding a second owner, which removes the link, keeps the screen open.
            .navigationDestination(for: Screen.self) { _ in
                Form { OwnersSection(app: app, settings: settings) }
                    .navigationTitle("Owners")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .task { storedBytes = await app.store.byteCount() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private enum Screen: Hashable {
        case owners
    }

    private var stored: String {
        app.scans.isEmpty ? "None" : "\(app.scans.count.counted("scan")) · \(storedBytes.formatted(.byteCount(style: .file)))"
    }
}
