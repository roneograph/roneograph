import SwiftUI

extension View {
    /// Limits the lines of text except at accessibility sizes, where truncating would hide most of it.
    func lineLimitUnlessAccessibilitySize(_ limit: Int) -> some View {
        modifier(AccessibilityLineLimit(limit: limit))
    }
}

private struct AccessibilityLineLimit: ViewModifier {
    let limit: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : limit)
    }
}
