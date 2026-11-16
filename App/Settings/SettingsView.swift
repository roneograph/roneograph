import ScannerKit
import ScannerModels
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EmailField(title: "Send to", email: $settings.value.email)
                } header: {
                    Text("Email")
                } footer: {
                    if !settings.value.email.isEmpty, !settings.value.hasValidEmail {
                        Text("This is not a valid email address.").foregroundStyle(.red)
                    } else {
                        Text("Fills in the recipient of the Email button. Needs an account in the Mail app.")
                    }
                }

                Section {
                    Label("\(settings.value.fileNameFormat.fileName(name: "Lumen Energy invoice", date: .now)).pdf", systemImage: "doc")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("Date first", isOn: $settings.value.fileNameFormat.datePrefix)
                    Picker("Separator", selection: $settings.value.fileNameFormat.separator) {
                        Text("a b").tag(FileNameFormat.Separator.space)
                        Text("a-b").tag(FileNameFormat.Separator.dash)
                        Text("a_b").tag(FileNameFormat.Separator.underscore)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Lowercase", isOn: $settings.value.fileNameFormat.lowercase)
                    Toggle("Ask for a name", isOn: $settings.value.askForName)
                } header: {
                    Text("File name")
                } footer: {
                    Text("The name is found in the text; the date is the one printed on the document, or the day of the scan.")
                }

                Section("Scanning") {
                    Picker("Keep scans for", selection: $settings.value.keepDays) {
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

extension PageLook {
    var title: String {
        switch self {
        case .color: "Color"
        case .gray: "Gray"
        }
    }
}
