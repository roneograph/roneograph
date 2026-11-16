import ScannerKit

extension Int {
    /// The count with its noun, for nouns whose plural takes an s: "1 page", "3 pages".
    public func counted(_ noun: String) -> String {
        self == 1 ? "1 \(noun)" : "\(self) \(noun)s"
    }
}

extension SendMethod {
    /// How a scan went out, on Home and in the confirmation.
    public var pastTense: String {
        switch self {
        case .email: "Emailed"
        case .files: "Saved"
        case .share: "Shared"
        }
    }
}
