import ScannerKit
import ScannerModels
import SwiftUI

/// Asked on the first tap on Email: where scans go from now on.
struct EmailQuestionView: View {
    let settings: SettingsStore
    let answered: () -> Void
    @State private var email = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Email scans to").font(.title3.bold())
                Text("The Email button fills in this address from now on. Change it anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            EmailField(title: "Email", email: $email)
                .focused($focused)
                .submitLabel(.continue)
                .onSubmit { if isValid { answer(email) } }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            VStack(spacing: 8) {
                Button { answer(email) } label: {
                    Text("Use This Address").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(!isValid)
                Button { answer("") } label: {
                    Text("Not Now").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .fontWeight(.semibold)
        }
        .padding()
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .onAppear { focused = true }
    }

    private var isValid: Bool { ScannerSettings.isValidEmail(email.trimmingCharacters(in: .whitespaces)) }

    private func answer(_ email: String) {
        settings.answerEmailQuestion(email)
        answered()
        dismiss()
    }
}
