import Foundation
import ScannerKit

/// Scans emailed one mail per owner, one after the other: the first mail of an owner may ask where its scans go, and a cancelled mail or question stops the rest.
@MainActor
public struct MailQueue {
    public enum Step: Equatable {
        /// Ask for the address of this owner before composing its mail.
        case askEmail(UUID)
        case compose
        case done
    }

    private let app: AppModel
    /// The scans still to email, one group per owner, the first one being sent.
    private var groups: [[ScanModel]]

    public init(_ scans: [ScanModel], app: AppModel) {
        self.app = app
        groups = app.byOwner(scans).map(\.scans)
    }

    /// The scans of the current mail, all of one owner.
    public var scans: [ScanModel] { groups.first ?? [] }

    /// The address of the owner of the current mail, when it has one.
    public var recipient: String? {
        scans.first.map(\.owner).flatMap { $0.hasValidEmail ? $0.email : nil }
    }

    /// What the current mail needs next.
    public var step: Step {
        guard let owner = scans.first?.owner else { return .done }
        return app.settings.shouldAskForEmail(for: owner.id) ? .askEmail(owner.id) : .compose
    }

    /// Without an answer, no mail goes out from here on.
    public mutating func closeQuestion(answered: Bool) {
        if !answered { groups = [] }
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
