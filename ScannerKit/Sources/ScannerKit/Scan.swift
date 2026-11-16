import Foundation

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
        revision += 1
    }
}

/// A value of a scan that can come from what the user corrected on a past document from the same issuer.
public enum RememberedValue: String, CaseIterable, Comparable, Sendable, Codable {
    case name, category, issuer

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
    case email, files, share
}

public struct Scan: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var created: Date
    /// Path of the PDF, without the extension, from `title`, the details and the file name format; a custom format may put it in folders.
    public var name: String
    /// The name as people read it: shown in the app and used as the email subject.
    public var title: String
    public var details = DocumentDetails()
    /// True once the user changed a detail; detection then stops replacing them.
    public var areDetailsEditedByUser = false
    /// True once the user renamed the scan; suggestions then stop replacing the name.
    public var isNamedByUser = false
    public var suggestions: [String] = []
    public var suggestedParts = SuggestedParts()
    /// How to recognize the issuer on the next document, to reuse what the user corrected.
    public var issuerKeys: [String] = []
    /// Nil until the first page is read, and for scans made before it was kept.
    public var read: ReadDocument?
    /// The values that come from what the user corrected on a past document, until changed.
    public var remembered: Set<RememberedValue> = []
    public var pages: [ScanPage] = []
    /// False while pages are being captured.
    public var isFinished = false
    public var sent: Date?
    public var sentBy: SendMethod?

    public init(id: UUID = UUID(), created: Date = .now, name: String, title: String? = nil) {
        self.id = id
        self.created = created
        self.name = name
        self.title = title ?? name
    }

    /// The file name of the PDF, without its folders: what Email, Share and the local copy use.
    public var fileName: String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    private enum CodingKeys: String, CodingKey {
        case id, created, name, title, details, areDetailsEditedByUser, isNamedByUser, suggestions, suggestedParts, issuerKeys, read, remembered, pages, isFinished, sent, sentBy
        case documentDate
    }

    /// Missing values keep their default, and the document date of older scans becomes a detail.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        created = try container.decode(Date.self, forKey: .created)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(DocumentDetails.self, forKey: .details) ?? DocumentDetails(date: container.decodeIfPresent(Date.self, forKey: .documentDate))
        areDetailsEditedByUser = try container.decodeIfPresent(Bool.self, forKey: .areDetailsEditedByUser) ?? false
        isNamedByUser = try container.decodeIfPresent(Bool.self, forKey: .isNamedByUser) ?? false
        suggestions = try container.decodeIfPresent([String].self, forKey: .suggestions) ?? []
        suggestedParts = try container.decodeIfPresent(SuggestedParts.self, forKey: .suggestedParts) ?? SuggestedParts()
        issuerKeys = try container.decodeIfPresent([String].self, forKey: .issuerKeys) ?? []
        read = try container.decodeIfPresent(ReadDocument.self, forKey: .read)
        remembered = try container.decodeIfPresent(Set<RememberedValue>.self, forKey: .remembered) ?? []
        pages = try container.decodeIfPresent([ScanPage].self, forKey: .pages) ?? []
        isFinished = try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
        sent = try container.decodeIfPresent(Date.self, forKey: .sent)
        sentBy = try container.decodeIfPresent(SendMethod.self, forKey: .sentBy)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(created, forKey: .created)
        try container.encode(name, forKey: .name)
        try container.encode(title, forKey: .title)
        try container.encode(details, forKey: .details)
        try container.encode(areDetailsEditedByUser, forKey: .areDetailsEditedByUser)
        try container.encode(isNamedByUser, forKey: .isNamedByUser)
        try container.encode(suggestions, forKey: .suggestions)
        try container.encode(suggestedParts, forKey: .suggestedParts)
        try container.encode(issuerKeys, forKey: .issuerKeys)
        try container.encodeIfPresent(read, forKey: .read)
        try container.encode(remembered, forKey: .remembered)
        try container.encode(pages, forKey: .pages)
        try container.encode(isFinished, forKey: .isFinished)
        try container.encodeIfPresent(sent, forKey: .sent)
        try container.encodeIfPresent(sentBy, forKey: .sentBy)
    }
}
