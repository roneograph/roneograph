import ScannerKit
import ScannerModels
import SwiftUI

struct SettingsView: View {
    let app: AppModel
    @Bindable var settings: SettingsStore
    @State private var choosingFolder = false
    @State private var folderFailed = false
    @State private var forgettingEverything = false
    @State private var deletingScans = false
    @State private var storedBytes = 0
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
                    Text("The name is found in the text, and a name you correct is reused for the next documents from the same issuer, with their own date and number where yours had them. The date of the document is the one printed on it, or the day of the scan when there is none.")
                }

                Section {
                    Toggle("Custom format", isOn: $settings.value.fileNameFormat.isCustom)
                    NavigationLink("Categories") { CategoriesView(settings: settings) }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("A custom format builds file names from the details of the document, such as {YYYY}-{MM} {ISSUER}, and can file scans into folders.")
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
                    Text("Corrections for \(settings.value.learnedIssuers.count.counted("issuer")), and which lines are your name and address. Scans and settings stay.")
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
                        ? "Scans stay until you delete them. PDFs already saved to Files or sent stay where they are."
                        : "Scans are deleted after this time, sent or not. PDFs already saved to Files or sent stay where they are.")
                }
                .confirmationDialog("Delete \(app.scans.count == 1 ? "the scan" : "all \(app.scans.count) scans")?", isPresented: $deletingScans, titleVisibility: .visible) {
                    Button("Delete All Scans", role: .destructive) {
                        app.deleteAllScans()
                        storedBytes = app.store.byteCount()
                    }
                } message: {
                    Text("Their pages and PDFs are deleted from this iPhone. PDFs you saved to Files or sent are not affected.")
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
            .onAppear { storedBytes = app.store.byteCount() }
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
