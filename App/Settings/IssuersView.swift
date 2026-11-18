import ScannerKit
import ScannerModels
import SwiftUI

/// What is remembered for each issuer, to forget one or all of them.
struct IssuersView: View {
    @Bindable var settings: SettingsStore
    @State private var search = ""
    @State private var forgettingAll = false

    var body: some View {
        Group {
            if settings.value.learnedIssuers.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Remembered", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(settings.value.nothingRemembered)
                }
            } else {
                list
            }
        }
        .navigationTitle("Issuers")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: some View {
        Form {
            Section {
                ForEach(issuers, id: \.keys) { issuer in
                    IssuerRow(issuer: issuer, owner: issuer.owner.map(settings.value.owner))
                        .swipeActions {
                            Button("Forget", role: .destructive) { settings.forget(issuer) }
                        }
                }
            } footer: {
                Text("Swipe to forget an issuer. Its next documents are named and sorted from what is read on the page.")
            }
            Section {
                Button("Forget All", role: .destructive) { forgettingAll = true }
                    .frame(maxWidth: .infinity)
            }
        }
        .searchable(text: $search)
        .confirmationDialog("Forget all issuers?", isPresented: $forgettingAll, titleVisibility: .visible) {
            Button("Forget All", role: .destructive) { settings.forgetAllIssuers() }
        } message: {
            Text("The corrections for \(settings.value.learnedIssuers.count.counted("issuer")) are forgotten.")
        }
    }

    private var issuers: [LearnedIssuer] {
        let all = settings.value.learnedIssuers
        guard !search.isEmpty else { return all }
        return all.filter { issuer in
            [issuer.title, issuer.label, issuer.issuer, issuer.recognizedBy].compactMap { $0 }.contains { $0.localizedStandardContains(search) }
        }
    }
}

private struct IssuerRow: View {
    let issuer: LearnedIssuer
    let owner: Owner?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(issuer.title).fontWeight(.semibold)
            Group {
                if let name = issuer.name { Text(nameLine(name)) }
                if let corrected = issuer.issuer { Text("Issuer: \(corrected)") }
                if let documentType = issuer.documentType { Text("Document type: \(documentType.rawValue)") }
                if let owner { Text("Owner: \(owner.name)") }
                if let recognizedBy = issuer.recognizedBy { Text(recognizedBy).foregroundStyle(.secondary) }
            }
            .font(.footnote)
        }
        .padding(.vertical, 2)
    }

    /// The remembered name, with what follows the next document shown as green tokens in braces.
    private func nameLine(_ pattern: NamePattern) -> AttributedString {
        var line = AttributedString("Name: ")
        for part in pattern.parts {
            switch part {
            case .text(let text): line += AttributedString(text)
            case .number: line += token("number")
            case .date(let style, _): line += token(style.token)
            }
        }
        return line
    }

    private func token(_ text: String) -> AttributedString {
        var token = AttributedString(" {\(text)} ")
        token.foregroundColor = .accentColor
        token.backgroundColor = Color.accentColor.opacity(0.14)
        return token
    }
}

private extension NamePattern.DateStyle {
    var token: String {
        switch self {
        case .day: "date"
        case .month, .monthName: "month"
        case .year: "year"
        }
    }
}
