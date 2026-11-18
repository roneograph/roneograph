import ScannerKit
import SwiftUI

/// How an owner's PDFs are named.
struct FileNameSection: View {
    @Binding var owner: Owner

    var body: some View {
        Section {
            Label("\(owner.fileNameFormat.sampleFileName).pdf", systemImage: "doc")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Toggle("Custom format", isOn: $owner.fileNameFormat.isCustom)
            if owner.fileNameFormat.isCustom {
                NavigationLink {
                    FileNameFormatView(format: $owner.fileNameFormat)
                } label: {
                    LabeledContent("Format", value: owner.fileNameFormat.template)
                }
            } else {
                Picker("Date", selection: $owner.fileNameFormat.datePosition) {
                    Text("None").tag(FileNameFormat.DatePosition.none)
                    Text("First").tag(FileNameFormat.DatePosition.start)
                    Text("Last").tag(FileNameFormat.DatePosition.end)
                }
                if owner.fileNameFormat.datePosition != .none {
                    Picker("Date format", selection: $owner.fileNameFormat.dateStyle) {
                        ForEach(FileNameFormat.DateStyle.allCases, id: \.self) { Text($0.format(.now)).tag($0) }
                    }
                }
            }
            if owner.fileNameFormat.isCustom || owner.fileNameFormat.datePosition != .none {
                Picker("Date of", selection: $owner.fileNameFormat.dateSource) {
                    Text("The document").tag(FileNameFormat.DateSource.document)
                    Text("The scan").tag(FileNameFormat.DateSource.scan)
                }
            }
            Picker("Separator", selection: $owner.fileNameFormat.separator) {
                Text("a b").tag(FileNameFormat.Separator.space)
                Text("a-b").tag(FileNameFormat.Separator.dash)
                Text("a_b").tag(FileNameFormat.Separator.underscore)
            }
            .pickerStyle(.segmented)
            Toggle("Lowercase", isOn: $owner.fileNameFormat.lowercase)
        } header: {
            Text("File name")
        } footer: {
            Text("The date of the document is the one printed on it, or the day of the scan when there is none. A custom format builds file names from the details of the document, such as {YYYY}-{MM} {ISSUER}.")
        }
    }
}
