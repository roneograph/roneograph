import ScannerKit
import ScannerModels
import SwiftUI

struct SettingsView: View {
    let app: AppModel
    @Bindable var settings: SettingsStore
    @State private var storedBytes = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                OwnersSection(app: app, settings: settings)

                Section {
                    NavigationLink("Categories") { CategoriesView(settings: settings) }
                } header: {
                    Text("Advanced")
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
                } header: {
                    Text("Memory")
                } footer: {
                    Text("Corrections are reused for the next documents from the same issuer. Nothing leaves this iPhone.")
                }

                Section {
                    LabeledContent("Stored", value: stored)
                } header: {
                    Text("Scans on this iPhone")
                } footer: {
                    Text("Scans not sent stay until you delete them. Sent scans leave this iPhone 24 hours after they were archived or shared.")
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

    private var stored: String {
        app.scans.isEmpty ? "None" : "\(app.scans.count.counted("scan")) · \(storedBytes.formatted(.byteCount(style: .file)))"
    }
}
