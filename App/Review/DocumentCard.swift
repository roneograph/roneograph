import ScannerKit
import ScannerModels
import SwiftUI

/// What a row of the document card edits in a sheet.
enum DocumentField: Identifiable {
    case name, issuer, number

    var id: Self { self }
}

/// The name and details of the scan, each row editing its own value: a sheet for text, a menu for the category, a calendar for the date.
struct DocumentCard: View {
    let scan: ScanModel
    let settings: SettingsStore
    let edit: (DocumentField) -> Void
    @State private var addingCategory = false
    @State private var newCategory = ""
    @State private var pickingDate = false
    @State private var forgetting = false
    @State private var addingOwner = false
    @State private var newOwner = ""

    private var details: DocumentDetails { scan.scan.details }
    private var remembered: Set<RememberedValue> { scan.scan.remembered }
    var body: some View {
        VStack(spacing: 0) {
            nameRow
            Divider().padding(.leading, 50)
            if settings.value.hasSeveralOwners {
                ownerRow
                Divider().padding(.leading, 50)
            }
            categoryRow
            Divider().padding(.leading, 50)
            textRow(.issuer, title: "Issuer", systemImage: "person.text.rectangle", value: details.issuer)
            Divider().padding(.leading, 50)
            dateRow
            Divider().padding(.leading, 50)
            textRow(.number, title: "Number", systemImage: "number", value: details.number)
            if !remembered.isEmpty {
                Divider()
                legend
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .alert("New Category", isPresented: $addingCategory) {
            TextField("Name", text: $newCategory)
            Button("Add") {
                if let category = settings.addCategory(newCategory) { update { $0.category = category } }
                newCategory = ""
            }
            Button("Cancel", role: .cancel) { newCategory = "" }
        }
        .alert("New Owner", isPresented: $addingOwner) {
            TextField("Name", text: $newOwner)
            Button("Add") {
                if let owner = settings.addOwner(newOwner) { scan.setOwner(owner.id) }
                newOwner = ""
            }
            Button("Cancel", role: .cancel) { newOwner = "" }
        } message: {
            Text("A company you scan documents for, such as your employer. Set its email address and folder in Settings.")
        }
    }

    /// Who the document belongs to, which decides where it goes and how it is named; tinted for that reason.
    private var ownerRow: some View {
        let owner = scan.owner
        return Menu {
            Picker("Owner", selection: Binding(get: { scan.hasDefaultOwner ? nil : owner.id }, set: { id in if let id { scan.setOwner(id) } })) {
                ForEach(settings.value.owners) { owner in
                    Label(owner.name, systemImage: owner.symbol.systemImage).tag(Optional(owner.id))
                }
            }
            Divider()
            Button("New Owner…", systemImage: "plus") { addingOwner = true }
        } label: {
            HStack(spacing: 14) {
                icon(owner.symbol.systemImage)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Owner")
                    if scan.hasDefaultOwner {
                        Text("Default").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    Text(owner.name).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.bold())
                }
                .foregroundStyle(.tint)
                mark(.owner)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(Color.accentColor.opacity(0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Owner, \(owner.name)\(scan.hasDefaultOwner ? ", default" : "")\(remembered.contains(.owner) ? ", remembered" : "")")
    }

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { edit(.name) } label: {
                HStack(spacing: 14) {
                    icon("character.cursor.ibeam")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Name").font(.caption).foregroundStyle(.secondary)
                        Text(scan.scan.title)
                            .font(.title3.bold())
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    chevron
                    mark(.name)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Name, \(scan.scan.title)\(remembered.contains(.name) ? ", remembered" : "")")
            .accessibilityHint("Renames the PDF")
            .accessibilityAddTraits(.isButton)
            HStack(spacing: 14) {
                Image(systemName: "doc").frame(width: 22)
                Text(fileName).lineLimit(2)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("File name \(fileName)")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var fileName: String {
        "\(scan.scan.name.replacing("/", with: " / ")).pdf"
    }

    private var categoryRow: some View {
        Menu {
            Picker("Category", selection: Binding(get: { details.category }, set: { category in update { $0.category = category } })) {
                ForEach(settings.value.categories(keeping: details.category), id: \.self) { Text($0.rawValue).tag($0) }
            }
            Divider()
            Button("New Category…", systemImage: "plus") { addingCategory = true }
        } label: {
            row(title: "Category", systemImage: "square.grid.2x2", remembered: .category) {
                HStack(spacing: 4) {
                    Text(details.category.rawValue)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.bold())
                }
                .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
    }

    private var dateRow: some View {
        Button { pickingDate = true } label: {
            row(title: "Date", systemImage: "calendar") {
                if let date = details.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.fill.tertiary, in: Capsule())
                } else {
                    add
                }
            }
        }
        .buttonStyle(.plain)
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

    private func textRow(_ field: DocumentField, title: String, systemImage: String, value: String?) -> some View {
        Button { edit(field) } label: {
            row(title: title, systemImage: systemImage, remembered: field == .issuer ? .issuer : nil) {
                HStack(spacing: 8) {
                    if let value {
                        Text(value).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        add
                    }
                    chevron
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func row(title: String, systemImage: String, remembered value: RememberedValue? = nil, @ViewBuilder value content: () -> some View) -> some View {
        HStack(spacing: 14) {
            icon(systemImage)
            Text(title)
            Spacer(minLength: 12)
            content()
            mark(value)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .contentShape(Rectangle())
    }

    /// A column at the trailing edge, so remembered values line up; absent when nothing is remembered.
    @ViewBuilder
    private func mark(_ value: RememberedValue?) -> some View {
        if !remembered.isEmpty {
            Group {
                if let value, remembered.contains(value) { RememberedMark() } else { Color.clear }
            }
            .frame(width: 18)
            .padding(.leading, -6)
        }
    }

    /// Says what the marks mean and how to undo them.
    private var legend: some View {
        HStack(spacing: 10) {
            RememberedMark().accessibilityHidden(true)
            Text("\(remembered.listed) remembered for \(details.issuerName)")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Forget") { forgetting = true }
                .fontWeight(.semibold)
        }
        .font(.footnote)
        .padding(.horizontal, 14).padding(.vertical, 10)
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

    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage).foregroundStyle(.tint).frame(width: 22)
    }

    private var add: some View {
        Text("Add").foregroundStyle(.tint)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
    }

    private func update(_ change: (inout DocumentDetails) -> Void) {
        var details = details
        change(&details)
        scan.setDetails(details)
    }
}

/// Edits the issuer or the number in a small sheet.
struct DetailTextView: View {
    let scan: ScanModel
    let field: DocumentField
    @State private var value = ""
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
            .onAppear {
                value = scan.scan.details[keyPath: detail] ?? ""
                selection = TextSelection(range: value.startIndex..<value.endIndex)
                focused = true
            }
        }
        .presentationDetents([.medium])
    }

    private var title: String { field == .issuer ? "Issuer" : "Number" }
    private var detail: WritableKeyPath<DocumentDetails, String?> { field == .issuer ? \.issuer : \.number }

    private var footer: String {
        guard field == .issuer else { return "The reference printed on the document, such as an invoice, contract or policy number." }
        guard scan.learnsIssuer else { return "Who sent the document." }
        return "Read on the page. A new issuer is reused for the next documents from the same issuer, along with the category."
    }

    private func save() {
        scan.setDetail(detail, to: value)
        dismiss()
    }
}
