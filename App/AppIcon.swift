import SwiftUI

struct AppIcon: View {
    let size: CGFloat

    var body: some View {
        Image(.logo)
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: size / 16, y: size / 32)
            .accessibilityLabel("Roneograph")
    }
}
