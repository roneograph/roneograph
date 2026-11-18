import Foundation
import ScannerKit

extension Int {
    /// The count with its noun, for nouns whose plural takes an s: "1 page", "3 pages".
    public func counted(_ noun: String) -> String {
        self == 1 ? "1 \(noun)" : "\(self) \(noun)s"
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

    /// What happens once the PDF is made, while the button waits for it: "Share opens when the PDF is ready".
    public var whenReady: String {
        switch self {
        case .paperless: "Archives when the PDF is ready"
        case .share: "Share opens when the PDF is ready"
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
        guard pageCount > 0 else { return "No pages" }
        let pages = pageCount.counted("page")
        if hasCurrentPDF, case .ready(_, let size) = pdf { return "\(pages) · \(size.fileSize)" }
        return switch pdf {
        case .failed: "\(pages) · the PDF could not be made"
        case .storageFull: "\(pages) · the iPhone storage is full"
        default: "\(pages) · preparing the PDF…"
        }
    }

    /// The pages, counting the ones still processed.
    var pageCount: Int {
        scan.pages.count + processing
    }
}

/// The line under the send buttons; `lead`, in bold before `text`, says what a button waiting for the PDF will do, and Connect Paperless follows `text` when `connectsPaperless`.
public struct SendFooter: Equatable {
    public var lead: String?
    public var text: String
    public var connectsPaperless = false
}

/// The buttons of the send bar before Delete: the one shown with its name, then the other way as a round button.
public struct SendButtons: Equatable {
    public var named: SendMethod
    /// "Archive", "Try Again", "Try Now", "Share".
    public var title: String
    /// Filled with the accent color, as it sends in a single tap; Share only opens the share sheet.
    public var isProminent: Bool
    public var round: SendMethod?
}

/// The line above the send buttons once a scan went out, or while it goes to Paperless.
public struct SendStatus: Equatable {
    public enum Kind: Equatable {
        case sent, uploading, failed
    }

    public var kind: Kind
    public var text: String
}

extension AppModel {
    /// Archive, named, then Share when the owner of the scan has a Paperless server; Share alone otherwise, and once the scan is archived, as Paperless refuses a file it already has.
    /// Archive reads "Try Again" once the upload failed and "Try Now" while it waits.
    public func sendButtons(for model: ScanModel) -> SendButtons {
        guard archives(model), !model.scan.isArchived else {
            return SendButtons(named: .share, title: SendMethod.share.title, isProminent: false)
        }
        let title = switch model.scan.archiving?.isInProgress {
        case true?: "Try Now"
        case false?: "Try Again"
        case nil: SendMethod.paperless.title
        }
        return SendButtons(named: .paperless, title: title, isProminent: true, round: .share)
    }

    /// Above the send buttons: "Archived to paperless.example.com · 10:42", "Shared · yesterday 18:02", "Waiting for paperless.example.com", "Not archived: <reason>"; nil until the scan goes out.
    public func sendStatus(of model: ScanModel, calendar: Calendar = .current, locale: Locale = .current) -> SendStatus? {
        let scan = model.scan
        let host = model.owner.paperlessHost ?? "Paperless"
        switch scan.archiving?.state {
        case .uploading: return SendStatus(kind: .uploading, text: "Archiving to \(host)…")
        case .waiting: return SendStatus(kind: .uploading, text: "Waiting for \(host)")
        case .failed(let reason): return SendStatus(kind: .failed, text: "Not archived: \(reason)")
        case nil: break
        }
        guard let sent = scan.sent else { return nil }
        let time = sent.date.shortTime(now: now(), calendar: calendar, locale: locale)
        return SendStatus(kind: .sent, text: sent.method == .paperless ? "Archived to \(host) · \(time)" : "Shared · \(time)")
    }

    /// Under the send buttons: "**Share opens when the PDF is ready** · 2 pages" while a button waits for the PDF, when the scan leaves this iPhone once it went out,
    /// otherwise where Archive sends it, or its owner with several owners, then its summary, followed by Connect Paperless when its owner has no server.
    public func sendFooter(for model: ScanModel, waiting: SendMethod?, calendar: Calendar = .current, locale: Locale = .current) -> SendFooter {
        if let waiting { return SendFooter(lead: waiting.whenReady, text: model.pageCount.counted("page")) }
        if model.scan.archiving?.isInProgress != true, let sent = model.scan.sent {
            return SendFooter(text: "Leaves this iPhone \(leaving(sent.date.addingTimeInterval(Self.sentScanLifetime), calendar: calendar, locale: locale))")
        }
        let text = [destination(of: model) ?? ownerLabel(of: model), model.summary].compactMap(\.self).joined(separator: " · ")
        return SendFooter(text: text, connectsPaperless: ownerToConnect(for: model) != nil)
    }

    /// "today at 10:42", "tomorrow at 10:42", "soon" once the time is past.
    private func leaving(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let now = now()
        guard date > now else { return "soon" }
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow at \(time)" }
        return "\(date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())) at \(time)"
    }

    /// Where Archive sends the scan: "To paperless.example.com".
    public func destination(of model: ScanModel) -> String? {
        guard archives(model), let host = model.owner.paperlessHost else { return nil }
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

/// A swipe action of a scan on Home.
public enum RowAction: Equatable, Sendable {
    /// Archive again after a failed upload.
    case archive, tryAgain, share

    public var title: String {
        switch self {
        case .archive: "Archive"
        case .tryAgain: "Try Again"
        case .share: "Share"
        }
    }

    public var method: SendMethod {
        self == .share ? .share : .paperless
    }
}

/// The card on Home that sends every finished scan not sent in one tap: to Paperless when every owner of the scans has a server, to the share sheet otherwise.
public struct NotSentOffer: Equatable {
    public var scans: [Scan]
    public var archives: Bool
    /// "6 scans not sent"
    public var title: String
    /// "6 pages · to Paperless", or the names of the scans.
    public var subtitle: String
    /// "Archive All", "Share All".
    public var button: String
}

extension AppModel {
    /// The swipe actions of a scan on Home, in order: Archive when its owner has a Paperless server, or Try Again once its upload failed, then Share; Share alone once it was sent, as Paperless refuses a file it already has.
    /// None while it is in progress, which has no PDF yet, or on its way to Paperless.
    public func swipeActions(for scan: Scan) -> [RowAction] {
        guard scan.isFinished, scan.archiving?.isInProgress != true else { return [] }
        let connected = isConnected(settings.value.owner(scan.owner?.id))
        if scan.archiving != nil { return connected ? [.tryAgain, .share] : [.share] }
        return connected && scan.sent == nil ? [.archive, .share] : [.share]
    }

    /// Offered once more than one finished scan was not sent.
    public var notSentOffer: NotSentOffer? {
        let scans = notSent
        guard scans.count > 1 else { return nil }
        let archives = scans.allSatisfy { isConnected(settings.value.owner($0.owner?.id)) }
        let pages = scans.reduce(0) { $0 + $1.pages.count }.counted("page")
        return NotSentOffer(
            scans: scans,
            archives: archives,
            title: "\(scans.count) scans not sent",
            subtitle: archives ? "\(pages) · to Paperless" : scans.map(\.title).joined(separator: ", "),
            button: archives ? "Archive All" : "Share All"
        )
    }
}

extension Date {
    /// "10:42" today, "yesterday 18:02", "Nov 12 18:02" before.
    func shortTime(now: Date, calendar: Calendar, locale: Locale) -> String {
        let time = formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(self, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(self, inSameDayAs: yesterday) { return "yesterday \(time)" }
        return "\(formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())) \(time)"
    }
}

extension Owner {
    /// "paperless.example.com"
    public var paperlessHost: String? {
        paperless.map { $0.url.host() ?? $0.url.absoluteString }
    }
}
