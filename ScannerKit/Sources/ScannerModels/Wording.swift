import ScannerKit

extension Int {
    /// The count with its noun, for nouns whose plural takes an s: "1 page", "3 pages".
    public func counted(_ noun: String) -> String {
        self == 1 ? "1 \(noun)" : "\(self) \(noun)s"
    }
}

extension ScanRetention {
    /// The choice in Settings: "7 days", "Forever".
    public var label: String {
        days.map { $0.counted("day") } ?? "Forever"
    }
}

extension DocumentDetails {
    /// The issuer in a sentence, "this issuer" when none is known.
    public var issuerName: String {
        issuer ?? "this issuer"
    }
}

extension PageLook {
    /// The look of a page, in Review and in the page viewer.
    public var title: String {
        switch self {
        case .color: "Color"
        case .gray: "Gray"
        }
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

extension Collection<RememberedValue> {
    /// "Name and category", in a fixed order, for the line that says what is remembered.
    public var listed: String {
        let words = sorted().map(\.rawValue)
        let text = words.count <= 1 ? words.joined() : words.dropLast().joined(separator: ", ") + " and " + words.last!
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

extension Collection<Scan> {
    /// The scan's name for one PDF, "3 documents" for several.
    public var mailSubject: String {
        count == 1 ? first!.title : count.counted("document")
    }

    /// Warns before sending again what already went out: "“Payslip” was already emailed", "2 were already sent".
    public var alreadySent: String? {
        let sent = filter { $0.sent != nil }
        guard let first = sent.first else { return nil }
        if sent.count > 1 { return "\(sent.count) were already sent" }
        return "“\(first.title)” was already \((first.sentBy ?? .email).pastTense.lowercased())"
    }
}
