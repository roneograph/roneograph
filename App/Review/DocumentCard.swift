import ScannerKit
import ScannerModels
import SwiftUI

/// What a row of the document card edits in a sheet.
enum DocumentField: Identifiable {
    case name, issuer, number, comment

    var id: Self { self }
}

/// The name of the scan and its details as chips, each editing its own value: a sheet for text, a menu for the owner and the document type, a calendar for the date;
/// then the comment, shown in full once there is one.
struct DocumentCard: View {
    let scan: ScanModel
    let settings: SettingsStore
    let edit: (DocumentField) -> Void
    @State private var addingDocumentType = false
    @State private var newDocumentType = ""
    @State private var pickingDate = false
    @State private var forgetting = false
    @State private var addingOwner = false
    @State private var newOwner = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var details: DocumentDetails { scan.scan.details }
    private var remembered: Set<RememberedValue> { scan.scan.remembered }

    var body: some View {
        Group {
            if scan.isReading {
                ReadingPlaceholder()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    nameButton
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        if settings.value.hasSeveralOwners { ownerChip }
                        documentTypeChip
                        textChip(.issuer, title: "Issuer", systemImage: "person.text.rectangle", value: details.issuer)
                        dateChip
                        textChip(.number, title: "Number", systemImage: "number", value: details.number.map { "No. \($0)" })
                        if scan.scan.comment == nil {
                            Button { edit(.comment) } label: { AddChip(title: "Comment") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add Comment")
                        }
                    }
                    if !remembered.isEmpty { legend }
                    if let comment = scan.scan.comment { commentButton(comment) }
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: scan.isReading)
        .alert("New Document Type", isPresented: $addingDocumentType) {
            TextField("Name", text: $newDocumentType)
            Button("Add") {
                if let documentType = settings.addDocumentType(newDocumentType) { update { $0.documentType = documentType } }
                newDocumentType = ""
            }
            Button("Cancel", role: .cancel) { newDocumentType = "" }
        }
        .alert("New Owner", isPresented: $addingOwner) {
            TextField("Name", text: $newOwner)
            Button("Add") {
                if let owner = settings.addOwner(newOwner) { scan.setOwner(owner.id) }
                newOwner = ""
            }
            Button("Cancel", role: .cancel) { newOwner = "" }
        } message: {
            Text("A company you scan documents for, such as your employer. Connect its Paperless server in Settings.")
        }
    }

    private var nameButton: some View {
        Button { edit(.name) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(scan.scan.title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.leading)
                    if remembered.contains(.name) { RememberedMark().font(.footnote) }
                    Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                }
                Label(fileName, systemImage: "doc")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimitUnlessAccessibilitySize(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Name, \(scan.scan.title)\(remembered.contains(.name) ? ", remembered" : ""), file name \(fileName)")
        .accessibilityHint("Renames the PDF")
        .accessibilityAddTraits(.isButton)
    }

    private var fileName: String {
        "\(scan.scan.name.replacing("/", with: " / ")).pdf"
    }

    /// Who the document belongs to, which decides where it goes and how it is named.
    private var ownerChip: some View {
        let owner = scan.owner
        return Menu {
            Section(scan.ownerCaption ?? "") {
                Picker("Owner", selection: Binding(get: { scan.hasDefaultOwner ? nil : owner.id }, set: { id in if let id { scan.setOwner(id) } })) {
                    ForEach(settings.value.owners) { owner in
                        Label(owner.name, systemImage: owner.symbol.systemImage).tag(Optional(owner.id))
                    }
                }
            }
            Divider()
            Button("New Owner…", systemImage: "plus") { addingOwner = true }
        } label: {
            Chip(text: owner.name, systemImage: owner.symbol.systemImage, isRemembered: remembered.contains(.owner), opensMenu: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(["Owner", owner.name, scan.ownerCaption, remembered.contains(.owner) ? "remembered" : nil].compactMap(\.self).joined(separator: ", "))
    }

    private var documentTypeChip: some View {
        Menu {
            Picker("Document Type", selection: Binding(get: { details.documentType }, set: { documentType in update { $0.documentType = documentType } })) {
                ForEach(settings.value.documentTypes(keeping: details.documentType), id: \.self) { Text($0.rawValue).tag($0) }
            }
            Divider()
            Button("New Document Type…", systemImage: "plus") { addingDocumentType = true }
        } label: {
            Chip(text: details.documentType.rawValue, systemImage: "square.grid.2x2", isRemembered: remembered.contains(.documentType), opensMenu: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Type, \(details.documentType.rawValue)\(remembered.contains(.documentType) ? ", remembered" : "")")
    }

    private var dateChip: some View {
        Button { pickingDate = true } label: {
            if let date = details.date {
                Chip(text: date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            } else {
                AddChip(title: "Date")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(details.date.map { "Date, \($0.formatted(date: .long, time: .omitted))" } ?? "Add Date")
        .popover(isPresented: $pickingDate) {
            VStack(spacing: 8) {
                DatePicker("Date", selection: Binding(get: { details.date ?? scan.scan.created }, set: { date in update { $0.date = date } }), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                if details.date != nil {
                    Divider()
                    Button("Clear Date", role: .destructive) {
                        update { $0.date = nil }
                        pickingDate = false
                    }
                }
            }
            .padding()
            .frame(width: 320)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func textChip(_ field: DocumentField, title: String, systemImage: String, value: String?) -> some View {
        let isRemembered = field == .issuer && remembered.contains(.issuer)
        return Button { edit(field) } label: {
            if let value {
                Chip(text: value, systemImage: systemImage, isRemembered: isRemembered)
            } else {
                AddChip(title: title)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.map { "\(title), \($0)\(isRemembered ? ", remembered" : "")" } ?? "Add \(title)")
    }

    private func commentButton(_ comment: String) -> some View {
        Button { edit(.comment) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "text.bubble").foregroundStyle(.tint)
                Text(comment)
                    .multilineTextAlignment(.leading)
                    .lineLimitUnlessAccessibilitySize(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Comment, \(comment)")
        .accessibilityAddTraits(.isButton)
    }

    /// Says that the marked values come from a past correction, and how to undo them.
    private var legend: some View {
        HStack(spacing: 6) {
            RememberedMark().accessibilityHidden(true)
            Text("Remembered for \(details.issuerName)")
                .foregroundStyle(.secondary)
                .lineLimitUnlessAccessibilitySize(1)
            Spacer(minLength: 8)
            Button("Forget") { forgetting = true }
                .fontWeight(.semibold)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remembered.listed) remembered for \(details.issuerName)")
        .confirmationDialog("Remembered for \(details.issuerName)", isPresented: $forgetting, titleVisibility: .visible) {
            ForEach(remembered.sorted(), id: \.self) { value in
                Button("Forget the \(value.rawValue.capitalized)", role: .destructive) { scan.forget([value]) }
            }
            if remembered.count > 1 {
                Button(remembered.count == 2 ? "Forget Both" : "Forget All", role: .destructive) { scan.forget(remembered) }
            }
        } message: {
            Text("This scan goes back to what was read on the page, and so will the next documents from \(details.issuerName).")
        }
    }

    private func update(_ change: (inout DocumentDetails) -> Void) {
        var details = details
        change(&details)
        scan.setDetails(details)
    }
}

/// Takes the place of the name and the details while the first page is read, with the height of the name so the pages do not move.
private struct ReadingPlaceholder: View {
    @State private var isDimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(" ").font(.title3.bold())
                Text(" ").font(.footnote)
            }
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the page…")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach([96, 132, 84], id: \.self) { width in
                    Text(" ")
                        .font(.subheadline)
                        .padding(.vertical, 7)
                        .frame(width: CGFloat(width))
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
            .opacity(isDimmed ? 0.4 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading the page")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) { isDimmed = true }
        }
    }
}

/// A detail of the scan: tinted when it opens a menu, with the remembered mark in place of its icon.
private struct Chip: View {
    let text: String
    let systemImage: String
    var isRemembered = false
    var opensMenu = false

    var body: some View {
        HStack(spacing: 5) {
            if isRemembered {
                RememberedMark()
            } else {
                Image(systemName: systemImage).foregroundStyle(.tint)
            }
            Text(text).lineLimitUnlessAccessibilitySize(1)
            if opensMenu {
                Image(systemName: "chevron.up.chevron.down").font(.caption2.bold())
            }
        }
        .font(.subheadline.weight(opensMenu ? .semibold : .regular))
        .foregroundStyle(opensMenu ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(opensMenu ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(Color(.secondarySystemBackground)), in: Capsule())
        .contentShape(Capsule())
    }
}

/// A missing detail, which adds it.
private struct AddChip: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "plus")
            .font(.subheadline)
            .foregroundStyle(.tint)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .contentShape(Capsule())
    }
}

/// Edits the issuer or the number in a small sheet.
struct DetailTextView: View {
    let scan: ScanModel
    let field: DocumentField
    @State private var value = ""
    /// The value when the sheet opened or when the page was read, to keep a value read while the user has not typed.
    @State private var shownValue = ""
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(title, text: $value, selection: $selection)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .autocorrectionDisabled(field == .number)
                        .textInputAutocapitalization(field == .number ? .never : .words)
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", action: save)
                }
            }
            .onChange(of: scan.scan.details[keyPath: detail]) { _, read in
                if value == shownValue {
                    value = read ?? ""
                    selection = TextSelection(range: value.startIndex..<value.endIndex)
                }
                shownValue = read ?? ""
            }
            .onAppear {
                value = scan.scan.details[keyPath: detail] ?? ""
                shownValue = value
                selection = TextSelection(range: value.startIndex..<value.endIndex)
                focused = true
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(value != shownValue)
    }

    private var title: String { field == .issuer ? "Issuer" : "Number" }
    private var detail: WritableKeyPath<DocumentDetails, String?> { field == .issuer ? \.issuer : \.number }

    private var footer: String {
        guard field == .issuer else { return "The reference printed on the document, such as an invoice, contract or policy number." }
        guard scan.learnsIssuer else { return "Who sent the document." }
        return "Read on the page. A new issuer is reused for the next documents from the same issuer, along with the document type."
    }

    private func save() {
        scan.applyDetail(detail, to: value, shownText: shownValue)
        dismiss()
    }
}
