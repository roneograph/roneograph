import ScannerKit
import ScannerModels
import SwiftUI

/// Renames a scan, showing which part of the file name the name gives and which parts the format adds.
struct NameView: View {
    let scan: ScanModel
    @State private var name = ""
    /// The name when the sheet opened or when the text was read, to keep a name read while the user has not typed.
    @State private var shownName = ""
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, selection: $selection)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
                if !scan.scan.suggestions.isEmpty || scan.rememberedName != nil {
                    Section("Suggestions") {
                        if let rememberedName = scan.rememberedName {
                            HStack {
                                Button { name = rememberedName } label: {
                                    HStack {
                                        Label {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(rememberedName)
                                                Text("Remembered for \(scan.scan.details.issuerName)").font(.caption).foregroundStyle(.secondary)
                                            }
                                        } icon: {
                                            RememberedMark()
                                        }
                                        Spacer()
                                        if rememberedName == name { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .accessibilityAddTraits(rememberedName == name ? .isSelected : [])
                                Button("Forget", role: .destructive) { scan.forget([.name]) }
                                    .font(.footnote.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                        }
                        ForEach(scan.scan.suggestions, id: \.self) { suggestion in
                            Button {
                                name = suggestion
                            } label: {
                                HStack {
                                    Label(suggestion, systemImage: "sparkles")
                                    Spacer()
                                    if suggestion == name { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
                                }
                            }
                            .accessibilityAddTraits(suggestion == name ? .isSelected : [])
                        }
                    }
                }
                Section {
                    FileNameParts(segments: segments)
                        .padding(.vertical, 4)
                } header: {
                    Text("File name")
                } footer: {
                    Text(scan.fileNameFormat.explanation(for: segments))
                }
                if let learning = scan.learning(forName: name) {
                    Section {
                        Label(learning, systemImage: "lightbulb")
                            .font(.footnote)
                    }
                }
                Section {
                } footer: {
                    Text("The name is also the email subject.")
                }
            }
            .navigationTitle("Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", action: save)
                }
            }
            .onChange(of: name) { _, value in
                let sanitized = FileNamer.sanitize(value)
                if sanitized != value { name = sanitized }
            }
            .onChange(of: scan.scan.title) { _, title in
                if name == shownName {
                    name = title
                    selection = TextSelection(range: name.startIndex..<name.endIndex)
                }
                shownName = title
            }
            .onAppear {
                name = scan.scan.title
                shownName = name
                selection = TextSelection(range: name.startIndex..<name.endIndex)
                focused = true
            }
        }
        .interactiveDismissDisabled(name != shownName)
    }

    private var segments: [FileNameSegment] {
        scan.fileNameSegments(for: scan.finalName(name)) + [FileNameSegment(".pdf", .text)]
    }

    private func save() {
        scan.applyName(name, shownName: shownName)
        dismiss()
    }
}
