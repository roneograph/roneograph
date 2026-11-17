import Foundation
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

extension ScannerSettings {
    /// What Forget Everything in Settings › Memory forgets.
    public var forgetEverythingMessage: String {
        let issuers = learnedIssuers.count.counted("issuer")
        return hasSeveralOwners
            ? "Corrections and owners remembered for \(issuers), which lines are your name and address, and which lines tell each owner. Scans, owners and settings stay."
            : "Corrections for \(issuers), and which lines are your name and address. Scans and settings stay."
    }

    /// In Settings › Memory › Issuers, before anything is remembered.
    public var nothingRemembered: String {
        "Correct the \(hasSeveralOwners ? "name, issuer, category or owner" : "name, issuer or category") of a scan, and it is reused for the next documents from the same issuer."
    }
}

extension DocumentDetails {
    /// The issuer in a sentence, "this issuer" when none is known.
    public var issuerName: String {
        issuer ?? "this issuer"
    }
}

extension FileNameFormat {
    /// Under the file name preview: what the format in Settings does with the name.
    public func explanation(for segments: [FileNameSegment]) -> String {
        if segments.contains(where: { $0.source == .name && $0.text.isEmpty }) {
            return "The format already shows what the suggested name says. Type a name to add to it."
        }
        if isCustom { return "Custom format in Settings: \(template)" }
        let date = switch datePosition {
        case .none: "no date"
        case .start: "date of the \(dateSource == .document ? "document" : "scan") first"
        case .end: "date of the \(dateSource == .document ? "document" : "scan") last"
        }
        let separator = switch self.separator {
        case .space: "spaces"
        case .dash: "dashes"
        case .underscore: "underscores"
        }
        return "Format in Settings: \([date, separator, lowercase ? "lowercase" : nil].compactMap { $0 }.joined(separator: ", "))."
    }
}

extension ScanModel {
    /// What renaming the scan to the typed name changes for the next documents from the same issuer; nil when nothing.
    public func learning(forName typed: String) -> String? {
        let name = finalName(typed)
        let issuer = scan.details.issuerName
        let replaces = rememberedName.map { $0 != name } ?? false
        guard let pattern = learnedPattern(for: name) else {
            return replaces ? "The name remembered for \(issuer) will be forgotten." : nil
        }
        let own = [pattern.follows.date ? "date" : nil, pattern.follows.number ? "number" : nil].compactMap { $0 }
        let with = own.isEmpty ? "" : ", with their own \(own.joined(separator: " and "))"
        let next = "The next documents from \(issuer) will be named the same way\(with)."
        return replaces ? "Replaces the name remembered for \(issuer). \(next)" : next
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
    /// The ways to send, in the order of the send bar.
    public static let inBarOrder: [SendMethod] = [.paperless, .email, .files, .share]

    /// The send button, as Settings names it.
    public var title: String {
        switch self {
        case .paperless: "Archive"
        case .email: "Email"
        case .files: "Save to Files"
        case .share: "Share"
        }
    }

    /// How a scan went out, on Home and in the confirmation.
    public var pastTense: String {
        switch self {
        case .email: "Emailed"
        case .files: "Saved"
        case .share: "Shared"
        case .paperless: "Archived"
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

extension Scan {
    /// Under the scan's name on Home: "In progress · 2 pages", "Emailed yesterday · 1 page", "Archiving… · 1 page", "Not sent · now · 3 pages".
    public var status: String {
        let pages = (pages.count + pending.count).counted("page")
        if !isFinished { return "In progress · \(pages)" }
        switch archiving?.state {
        case .uploading: return "Archiving… · \(pages)"
        case .waiting: return "Waiting for Paperless · \(pages)"
        case .failed(let reason): return "Not archived: \(reason)"
        case nil: break
        }
        if let sent { return "\(sent.method.pastTense) \(Self.relative(sent.date)) · \(pages)" }
        return "Not sent · \(Self.relative(created)) · \(pages)"
    }

    private static func relative(_ date: Date) -> String {
        date.timeIntervalSinceNow > -60 ? "now" : date.formatted(.relative(presentation: .named))
    }
}

extension Int {
    /// A size in bytes, as for files: "1.2 MB".
    var fileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}

extension ScanModel {
    /// Under the send buttons in Review: "3 pages · 1.2 MB", or where the PDF is at.
    public var summary: String {
        let count = scan.pages.count + processing
        guard count > 0 else { return "No pages" }
        let pages = count.counted("page")
        if let size = [self].currentPDFSize { return "\(pages) · \(size.fileSize)" }
        return switch pdf {
        case .failed: "\(pages) · the PDF could not be made"
        case .storageFull: "\(pages) · the iPhone storage is full"
        default: "\(pages) · preparing the PDF…"
        }
    }
}

@MainActor
extension Collection<ScanModel> {
    /// Under the send buttons on Home: "2 documents · 5 pages · 1.2 MB", or where the PDFs are at.
    public var selectionSummary: String {
        guard !isEmpty else { return "Select the scans to send" }
        let pages = reduce(0) { $0 + $1.scan.pages.count }.counted("page")
        let failed = filter { $0.pdf == .failed || $0.pdf == .storageFull }.count
        let state = switch failed {
        case 0: currentPDFSize?.fileSize ?? "preparing the PDFs…"
        case _ where contains(where: { $0.pdf == .storageFull }): "the iPhone storage is full"
        case 1: count == 1 ? "the PDF could not be made" : "a PDF could not be made"
        default: "\(failed) PDFs could not be made"
        }
        return "\(count.counted("document")) · \(pages) · \(state)"
    }

    /// The size of the PDFs, once each is made from its scan as it is now.
    var currentPDFSize: Int? {
        guard !isEmpty, allSatisfy(\.hasCurrentPDF) else { return nil }
        return reduce(0) { total, model in
            if case .ready(_, let size) = model.pdf { total + size } else { total }
        }
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
        guard let first = sent.first, let method = first.sent?.method else { return nil }
        if sent.count > 1 { return "\(sent.count) were already sent" }
        return "“\(first.title)” was already \(method.pastTense.lowercased())"
    }
}

extension AppModel {
    /// An owner's row in Settings, read by VoiceOver: "Personal, default, sends by Archive, Email".
    public func summary(of owner: Owner) -> String {
        let methods = SendMethod.inBarOrder.filter { isSet($0, for: owner) }.map(\.title)
        let parts: [String?] = [
            owner.name,
            owner.id == settings.value.defaultOwnerID ? "default" : nil,
            methods.isEmpty ? "nothing set to send" : "sends by \(methods.joined(separator: ", "))",
        ]
        return parts.compactMap(\.self).joined(separator: ", ")
    }
}
