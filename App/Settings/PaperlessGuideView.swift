import ScannerKit
import SwiftUI
import UIKit

/// What Archive sends to Paperless-ngx, the placeholders storage paths read it with, and storage paths to start from.
struct PaperlessGuideView: View {
    let owner: Owner
    @State private var copied: String?

    var body: some View {
        Form {
            Section {
                field("Title", from: "The scan's name", placeholder: "{{ title }}")
                field("Created", from: "The date on the document", placeholder: "{{ created_year }}, {{ created_month }}, {{ created_day }}")
                field("Correspondent", from: "The issuer", placeholder: "{{ correspondent }}")
                field("Document type", from: "The category", placeholder: "{{ document_type }}")
                field("Owner", from: ownerName, placeholder: "{{ custom_fields|get_cf_value('\(Paperless.ownerField)') }}")
                field("Original name", from: "The file name", placeholder: "{{ original_name }}")
            } header: {
                Text("Fields")
            } footer: {
                Text("Correspondents, document types and the \(Paperless.ownerField) field are created when missing; the owner needs Paperless-ngx 2.19 or later. In a storage path, a missing value reads as none.")
            }
            Section {
                ForEach(storagePaths, id: \.template) { path in
                    storagePath(path.template, gives: path.example)
                }
            } header: {
                Text("Storage paths to start from")
            } footer: {
                Text("Paste a path in a new storage path in Paperless-ngx, under Manage › Storage Paths, then tap Connect to pick it.")
            }
        }
        .navigationTitle("What Archive Sends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ownerName: String {
        let name = owner.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "The owner" : name
    }

    private func field(_ name: String, from source: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                Spacer()
                Text(source).font(.footnote).foregroundStyle(.secondary)
            }
            Text(placeholder)
                .font(.footnote.monospaced())
                .foregroundStyle(.tint)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private func storagePath(_ template: String, gives example: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.tint)
                Text("\(example).pdf")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(copied == template ? "Copied" : "Copy", systemImage: copied == template ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = template
                copied = template
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .combine)
    }

    /// Storage paths with what they give for the made-up invoice of the file name format, sent by this owner.
    private var storagePaths: [(template: String, example: String)] {
        let ownerValue = "{{ custom_fields|get_cf_value('\(Paperless.ownerField)', 'Unsorted') }}"
        let name = owner.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerExample = name.isEmpty ? "Unsorted" : name
        let year = String(Calendar(identifier: .gregorian).component(.year, from: .now))
        let originalName = owner.fileNameFormat.sampleFileName.split(separator: "/").last.map(String.init) ?? ""
        return [
            ("{{ created_year }}/{{ correspondent }}/{{ title }}", "\(year)/\(SampleDocument.issuer)/\(SampleDocument.name)"),
            ("\(ownerValue)/{{ document_type }}/{{ original_name }}", "\(ownerExample)/\(SampleDocument.category.rawValue)/\(originalName)"),
            ("\(ownerValue)/{{ created_year }}/{{ original_name }}", "\(ownerExample)/\(year)/\(originalName)"),
        ]
    }
}
