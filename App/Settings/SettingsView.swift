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
                    TextField("Send to", text: $settings.value.email, prompt: Text("you@example.com"))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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

                Section {
                    Picker("Size", selection: $settings.value.quality) {
                        ForEach(PDFQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Default paper", selection: $settings.value.paper) {
                        Text("A4").tag(Paper.a4)
                        Text("Letter").tag(Paper.letter)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("PDF")
                } footer: {
                    Text("Pages get the size of what was scanned: A4, Letter, a card. The default paper is used when it is not clear.")
                }

                Section("Scanning") {
                    Toggle("Auto capture", isOn: $settings.value.autoCapture)
                    LookPicker(look: $settings.value.look)
                    Picker("Keep scans for", selection: $settings.value.keepDays) {
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                }

                Section {
                } footer: {
                    VStack(spacing: 4) {
                        Text("No ads, no account, no tracking.")
                        Text("Open source, MIT license · [Source code](https://github.com/roneograph/roneograph)")
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    }
                    .frame(maxWidth: .infinity)
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
        case .blackAndWhite: "B&W"
        case .photo: "Photo"
        }
    }
}

extension PDFQuality {
    var title: String {
        switch self {
        case .small: "Small"
        case .balanced: "Balanced"
        case .best: "Best"
        }
    }

    var purpose: String {
        switch self {
        case .small: "Email, upload limits"
        case .balanced: "Reading on screen, archiving"
        case .best: "Printing, very small print"
        }
    }
}
