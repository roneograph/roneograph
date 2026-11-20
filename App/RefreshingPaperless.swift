import SwiftUI

extension View {
    /// Pull to refresh reads the Paperless correspondents and document types again, offered only when an owner is connected.
    @ViewBuilder
    func refreshingPaperless(if isConnected: Bool, _ read: @escaping @Sendable () async -> Void) -> some View {
        if isConnected { refreshable(action: read) } else { self }
    }
}
