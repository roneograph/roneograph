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
    /// Under the names and addresses of an owner in Settings: how else its names are recognized, or what to type for them to be.
    public func addressedToFooter(of ownerID: UUID, region: String?, language: String?) -> String {
        let owner = owner(ownerID)
        let forms = owner.otherForms(region: region, language: language)
        if !forms.isEmpty { return "Also recognized: \(forms.joined(separator: ", ")). Case, accents and word order do not matter." }
        if owner.hasPlaceholderName { return "Type your name above: documents addressed to you are then recognized." }
        return "Name this owner as on its mail, with a first and a last name: documents addressed to it are then recognized."
    }

    /// The other owners with one of the addresses of an owner, which only names can then tell apart.
    public func sharedAddressWarning(of ownerID: UUID) -> String? {
        let addresses = owner(ownerID).addresses
        let others = owners.filter { other in
            other.id != ownerID && other.addresses.contains { address in addresses.contains { Owner.isSameAddress($0, as: address) } }
        }.map(\.name)
        guard !others.isEmpty else { return nil }
        return "\(others.formatted(.list(type: .and).locale(Locale(identifier: "en")))) \(others.count == 1 ? "has" : "have") this address too: only the names tell them apart."
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
    /// The send button: "Archive", "Share".
    public var title: String {
        switch self {
        case .paperless: "Archive"
        case .share: "Share"
        }
    }

    /// How a scan went out, on Home and in the confirmation.
    public var pastTense: String {
        switch self {
        case .paperless: "Archived"
        case .share: "Shared"
        }
    }

    /// What happens once the PDFs of that many scans are made, while the button waits for them: "Share opens when the PDF is ready".
    public func whenReady(pdfs count: Int) -> String {
        let pdfs = count > 1 ? "the PDFs are" : "the PDF is"
        return switch self {
        case .paperless: "Archives when \(pdfs) ready"
        case .share: "Share opens when \(pdfs) ready"
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
    /// Under the scan's name on Home: "In progress · 2 pages", "Shared yesterday · 1 page", "Archiving… · 1 page", "Not sent · now · 3 pages".
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

    /// "2 pages", counting the pages still processed.
    var pageCount: String {
        reduce(0) { $0 + $1.scan.pages.count + $1.processing }.counted("page")
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
    /// Warns before sending again what already went out: "“Payslip” was already archived", "2 were already sent".
    public var alreadySent: String? {
        let sent = filter { $0.sent != nil }
        guard let first = sent.first, let method = first.sent?.method else { return nil }
        if sent.count > 1 { return "\(sent.count) were already sent" }
        return "“\(first.title)” was already \(method.pastTense.lowercased())"
    }
}

/// The line under the send buttons; `lead`, in bold before `text`, says what a button waiting for the PDFs will do.
public struct SendFooter: Equatable {
    public var lead: String?
    public var text: String
}

extension AppModel {
    /// Under the send buttons: "**Share opens when the PDF is ready** · 2 pages" while a button waits for the PDFs, otherwise where the button shown with its name sends, or the owner of the scans with several owners, then the summary.
    public func sendFooter(for models: [ScanModel], waiting: SendMethod?, summary: String) -> SendFooter {
        if let waiting { return SendFooter(lead: waiting.whenReady(pdfs: models.count), text: models.pageCount) }
        return SendFooter(text: [destination(of: models) ?? ownerLabel(of: models), summary].compactMap(\.self).joined(separator: " · "))
    }

    /// Where Archive sends the scans when they all have one owner: "To paperless.example.com".
    public func destination(of models: [ScanModel]) -> String? {
        let owners = Self.owners(of: models)
        guard owners.count == 1, namedSendMethod(for: models) == .paperless, let host = owners[0].paperlessHost else { return nil }
        return "To \(host)"
    }

    /// An owner's row in Settings, read by VoiceOver: "Me, default, archives to paperless.example.com".
    public func summary(of owner: Owner) -> String {
        let parts: [String?] = [
            owner.name,
            owner.id == settings.value.defaultOwnerID ? "default" : nil,
            archivesTo(owner).map { "archives to \($0)" } ?? "Paperless not connected",
        ]
        return parts.compactMap(\.self).joined(separator: ", ")
    }

    /// The host of the owner's Paperless server once it is connected.
    public func archivesTo(_ owner: Owner) -> String? {
        isConnected(owner) ? owner.paperlessHost : nil
    }
}

extension Owner {
    /// "paperless.example.com"
    public var paperlessHost: String? {
        paperless.map { $0.url.host() ?? $0.url.absoluteString }
    }
}
