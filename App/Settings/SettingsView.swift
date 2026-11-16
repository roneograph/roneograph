import ScannerKit
import ScannerModels
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var choosingFolder = false
    @State private var folderFailed = false
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
                    Button { choosingFolder = true } label: {
                        LabeledContent("Folder", value: settings.value.archiveFolder?.name ?? "Choose…")
                    }
                    if settings.value.archiveFolder != nil {
                        Button("Forget Folder", role: .destructive) { settings.value.archiveFolder = nil }
                    }
                } header: {
                    Text("Save to Files")
                } footer: {
                    Text("The Save button puts PDFs in this folder without asking each time.")
                }
                .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                    guard case .success(let url) = result else { return }
                    do { try settings.chooseArchiveFolder(url) } catch { folderFailed = true }
                }
                .alert("This folder cannot be used", isPresented: $folderFailed) {
                    Button("OK") {}
                }

                Section {
                    Label("\(settings.value.fileNameFormat.sampleFileName).pdf", systemImage: "doc")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if settings.value.fileNameFormat.isCustom {
                        NavigationLink {
                            FileNameFormatView(settings: settings)
                        } label: {
                            LabeledContent("Format", value: settings.value.fileNameFormat.template)
                        }
                    } else {
                        Picker("Date", selection: $settings.value.fileNameFormat.datePosition) {
                            Text("None").tag(FileNameFormat.DatePosition.none)
                            Text("First").tag(FileNameFormat.DatePosition.start)
                            Text("Last").tag(FileNameFormat.DatePosition.end)
                        }
                        if settings.value.fileNameFormat.datePosition != .none {
                            Picker("Date format", selection: $settings.value.fileNameFormat.dateStyle) {
                                ForEach(FileNameFormat.DateStyle.allCases, id: \.self) { Text($0.format(.now)).tag($0) }
                            }
                        }
                    }
                    if settings.value.fileNameFormat.isCustom || settings.value.fileNameFormat.datePosition != .none {
                        Picker("Date of", selection: $settings.value.fileNameFormat.dateSource) {
                            Text("The document").tag(FileNameFormat.DateSource.document)
                            Text("The scan").tag(FileNameFormat.DateSource.scan)
                        }
                    }
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
                    Text("The name is found in the text, and a name you correct is reused for the next document that gets the same suggestion. The date of the document is the one printed on it, or the day of the scan when there is none.")
                }

                Section {
                    Toggle("Custom format", isOn: $settings.value.fileNameFormat.isCustom)
                    NavigationLink("Categories") { CategoriesView(settings: settings) }
                    if settings.hasLearned {
                        Button("Forget Corrections", role: .destructive) { settings.forgetLearned() }
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("A custom format builds file names from the details of the document, such as {YYYY}-{MM} {ISSUER}, and can file scans into folders. Forgetting corrections also forgets names, issuers and categories you corrected, and which lines are your own name and address.")
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
