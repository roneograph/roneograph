import Foundation
import ScannerKit

/// Scans emailed one mail per owner, one after the other; a cancelled mail stops the rest.
@MainActor
public struct MailQueue {
    private let app: AppModel
    /// The scans still to email, one group per owner, the first one being sent.
    private var groups: [[ScanModel]]

    public init(_ scans: [ScanModel], app: AppModel) {
        self.app = app
        groups = app.byOwner(scans).map(\.scans)
    }

    /// The scans of the current mail, all of one owner; empty once every mail went out or one was cancelled.
    public var scans: [ScanModel] { groups.first ?? [] }

    /// The address of the owner of the current mail, when it has one.
    public var recipient: String? {
        scans.first.map(\.owner).flatMap { $0.hasValidEmail ? $0.email : nil }
    }

    /// A sent mail marks its scans sent and returns them, and the next owner's mail comes; a cancelled one stops the rest.
    @discardableResult
    public mutating func closeMail(sent: Bool) -> [ScanModel] {
        guard sent, !groups.isEmpty else {
            groups = []
            return []
        }
        let mail = groups.removeFirst()
        app.didSend(mail, by: .email)
        return mail
    }
}
