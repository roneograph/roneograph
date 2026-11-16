import SwiftUI

extension ShapeStyle where Self == Color {
    /// Marks what comes from a past correction, apart from the green of the controls.
    static var remembered: Color { .purple }
}

/// The glyph of a remembered value.
struct RememberedMark: View {
    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .foregroundStyle(.remembered)
            .accessibilityLabel("Remembered")
    }
}
