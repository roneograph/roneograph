import SwiftUI

/// An email address field: email keyboard, no capitals, no corrections.
struct EmailField: View {
    let title: String
    @Binding var email: String

    var body: some View {
        TextField(title, text: $email, prompt: Text(verbatim: "you@example.com"))
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}
