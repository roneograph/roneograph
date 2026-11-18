import Foundation

public struct CleanupSettings: Equatable, Codable, Sendable {
    /// Nil picks the look from the page content.
    public var look: PageLook?

    public init(look: PageLook? = nil) {
        self.look = look
    }
}

public struct ScanPage: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    /// Where the page is in the original photo, nil when the whole photo is the page.
    public var quad: Quad?
    /// Where the page was found when it was captured, to go back to it after a manual crop.
    public var detectedQuad: Quad?
    public var analysis: PageAnalysis
    public var cleanup: CleanupSettings
    /// Bumped on every change, so cached images are reloaded.
    public var revision: Int
    /// Bumped on every recrop, which writes a new flat page, so the one scan.json points to stays until the scan is saved.
    public var crop = 0

    public init(id: UUID = UUID(), quad: Quad?, analysis: PageAnalysis, cleanup: CleanupSettings = .init(), revision: Int = 0) {
        self.id = id
        self.quad = quad
        self.detectedQuad = quad
        self.analysis = analysis
        self.cleanup = cleanup
        self.revision = revision
    }

    public var look: PageLook { cleanup.look ?? analysis.suggestedLook }

    /// Turns the page a quarter turn clockwise.
    public mutating func rotate() {
        analysis.orientation = analysis.orientation.turned
    }
}

/// A photo captured but not made into a page yet; it is saved first, so the page is made even after the app was quit.
public struct PendingPage: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    /// Where the page was seen live, when it is not found on the photo.
    public var liveQuad: Quad?

    public init(id: UUID = UUID(), liveQuad: Quad?) {
        self.id = id
        self.liveQuad = liveQuad
    }
}

/// A value of a scan that can come from what the user corrected on a past document from the same issuer.
public enum RememberedValue: String, CaseIterable, Comparable, Sendable, Codable {
    case name, category, issuer, owner

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// What was read on the first page, before what the user corrected for the same issuer was applied.
public struct ReadDocument: Equatable, Sendable, Codable {
    public var details: DocumentDetails
    public var parts: SuggestedParts

    public init(details: DocumentDetails, parts: SuggestedParts) {
        self.details = details
        self.parts = parts
    }
}

public enum SendMethod: String, Equatable, Sendable, Codable {
    case paperless, share
}

/// A scan on its way to the owner's Paperless-ngx server; it counts as sent only once the server took it.
public struct Archiving: Equatable, Sendable, Codable {
    public enum State: Equatable, Sendable, Codable {
        case uploading
        /// Tried again later, for the reason given.
        case waiting(String)
        /// Not tried again until the user asks.
        case failed(String)
    }

    public var state: State
    /// The failed tries since the user last sent it.
    public var retries: Int

    public init(state: State = .uploading, retries: Int = 0) {
        self.state = state
        self.retries = retries
    }

    public var isInProgress: Bool {
        if case .failed = state { false } else { true }
    }
}

public struct Sent: Equatable, Sendable, Codable {
    public var date: Date
    public var method: SendMethod

    public init(date: Date, method: SendMethod) {
        self.date = date
        self.method = method
    }
}

/// Who a scan belongs to, kept as it was given so changing the default owner moves no scan.
public struct ScanOwner: Equatable, Sendable, Codable {
    public var id: UUID
    /// True when nothing told the owner and the scan got the default one; reading the page may still replace it.
    public var isDefault: Bool
    /// What on the page told the owner, when its name or address did.
    public var clue: OwnerClue?

    public init(id: UUID, isDefault: Bool = false, clue: OwnerClue? = nil) {
        self.id = id
        self.isDefault = isDefault
        self.clue = clue
    }
}

public struct Scan: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var created: Date
    /// File name of the PDF, without the extension, from `title`, the details and the file name format.
    public var name: String
    /// The name as people read it: shown in the app and sent to Paperless as the title.
    public var title: String
    public var details = DocumentDetails()
    /// What the page does not say, such as who was at a lunch: written as the PDF's subject and sent with it; nil when there is none.
    public var comment: String?
    /// True once the user changed a detail; detection then stops replacing them.
    public var areDetailsEditedByUser = false
    /// True once the user renamed the scan; suggestions then stop replacing the name.
    public var isNamedByUser = false
    public var suggestions: [String] = []
    public var suggestedParts = SuggestedParts()
    /// How to recognize the issuer on the next document, to reuse what the user corrected.
    public var issuerKeys: [String] = []
    /// Read on the page, remembered per issuer, chosen, or the default owner; nil until the scan has a model, which gives it one.
    public var owner: ScanOwner?
    /// Nil until the first page is read.
    public var read: ReadDocument?
    /// The values that come from what the user corrected on a past document, until changed.
    public var remembered: Set<RememberedValue> = []
    public var pages: [ScanPage] = []
    /// Captured after the pages, in order, and not made into pages yet.
    public var pending: [PendingPage] = []
    public var sent: Sent?
    /// Set while the scan goes to Paperless, or when it could not.
    public var archiving: Archiving?

    /// Whether the owner's Paperless server took the scan, which it would refuse again.
    public var isArchived: Bool { sent?.method == .paperless }

    public init(id: UUID = UUID(), created: Date = .now, name: String, title: String? = nil) {
        self.id = id
        self.created = created
        self.name = name
        self.title = title ?? name
    }
}
