import Foundation

public struct ScannerSettings: Equatable, Sendable, Codable {
    /// Never empty; with a single owner, the app never mentions owners.
    public private(set) var owners: [Owner]
    /// The owner of the documents nothing on the page tells the owner of.
    public var defaultOwnerID: UUID {
        didSet { if !owners.contains(where: { $0.id == defaultOwnerID }) { defaultOwnerID = oldValue } }
    }
    /// Set once the review screen tip about tapping pages was closed, or a page was opened.
    public var dismissedPageTip = false
    public var autoCapture = true
    /// Opens the rename sheet when the review screen first shows.
    public var askForName = false
    /// Categories the user added to the built-in ones.
    public var categories: [DocumentCategory] = []
    /// The issuer, category, name and owner the user gave to documents from an issuer, most recent first.
    public var learnedIssuers: [LearnedIssuer] = []
    /// Header lines seen on past scans, to recognize the user's own name and address.
    public var headerLines: [HeaderLine] = []
    public var keepScans = ScanRetention.week
    /// Whether the send bar has Save to Files and Share; Archive and Email show once the owner has a server or an address.
    public var showsSaveToFiles = true
    public var showsShare = true
    /// Set once the Home card pointing to Settings for Email and Paperless was closed.
    public var dismissedSendSetup = false

    public init() {
        let personal = Owner(name: "Personal", symbol: .house)
        owners = [personal]
        defaultOwnerID = personal.id
    }

    /// Settings saved by an older build keep their values; the keys added since take their defaults.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let owners = try container.decode(.owners, or: owners)
        if !owners.isEmpty { self.owners = owners }
        let defaultOwnerID = try container.decode(.defaultOwnerID, or: self.owners[0].id)
        self.defaultOwnerID = hasOwner(defaultOwnerID) ? defaultOwnerID : self.owners[0].id
        dismissedPageTip = try container.decode(.dismissedPageTip, or: dismissedPageTip)
        autoCapture = try container.decode(.autoCapture, or: autoCapture)
        askForName = try container.decode(.askForName, or: askForName)
        categories = try container.decode(.categories, or: categories)
        learnedIssuers = try container.decode(.learnedIssuers, or: learnedIssuers)
        headerLines = try container.decode(.headerLines, or: headerLines)
        keepScans = try container.decode(.keepScans, or: keepScans)
        showsSaveToFiles = try container.decode(.showsSaveToFiles, or: showsSaveToFiles)
        showsShare = try container.decode(.showsShare, or: showsShare)
        dismissedSendSetup = try container.decode(.dismissedSendSetup, or: dismissedSendSetup)
    }

    public var hasSeveralOwners: Bool { owners.count > 1 }

    /// The owner with this ID; the default owner when there is none or it was deleted.
    public func owner(_ id: UUID?) -> Owner {
        owners.first { $0.id == id } ?? defaultOwner
    }

    public func hasOwner(_ id: UUID?) -> Bool {
        owners.contains { $0.id == id }
    }

    public var defaultOwner: Owner {
        get { owners.first { $0.id == defaultOwnerID } ?? owners[0] }
        set { updateOwner(newValue) }
    }

    /// Replaces the owner with the same ID; does nothing when there is none.
    public mutating func updateOwner(_ owner: Owner) {
        guard let index = owners.firstIndex(where: { $0.id == owner.id }) else { return }
        owners[index] = owner
    }

    public mutating func addOwner(_ owner: Owner) {
        owners.append(owner)
    }

    /// Removes an owner, never the default one, so there is always one left.
    public mutating func removeOwner(_ id: UUID) {
        guard id != defaultOwnerID else { return }
        owners.removeAll { $0.id == id }
    }

    /// The built-in categories, then the user's, Other last.
    public var allCategories: [DocumentCategory] {
        DocumentCategory.builtIn.dropLast() + categories.sorted() + [.other]
    }

    /// The categories to pick from, with the current one even when the user removed it since.
    public func categories(keeping current: DocumentCategory) -> [DocumentCategory] {
        let all = allCategories
        return all.contains(current) ? all : all + [current]
    }

    public static func isValidEmail(_ email: String) -> Bool {
        email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s.]{2,}/) != nil
    }
}

/// How long sent scans stay on the device before they are deleted; scans never sent stay.
public enum ScanRetention: String, CaseIterable, Sendable, Codable {
    case day, week, month, forever

    /// Nil when scans are never deleted.
    public var days: Int? {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .forever: nil
        }
    }
}

/// What the user corrected on documents from one issuer, recognized by any of its keys; nil when not corrected.
public struct LearnedIssuer: Equatable, Sendable, Codable {
    public var keys: [String]
    /// The issuer of the last corrected document, to show who this is.
    public var label: String?
    public var issuer: String?
    public var category: DocumentCategory?
    public var name: NamePattern?
    public var owner: UUID?

    public init(keys: [String], label: String? = nil, issuer: String? = nil, category: DocumentCategory? = nil, name: NamePattern? = nil, owner: UUID? = nil) {
        self.keys = keys
        self.label = label
        self.issuer = issuer
        self.category = category
        self.name = name
        self.owner = owner
    }

    /// Whether anything is left to reuse for the next documents.
    public var isEmpty: Bool {
        issuer == nil && category == nil && name == nil && owner == nil
    }

    /// Who this is: the corrected issuer, the issuer of the last document, or how it is recognized.
    public var title: String {
        issuer ?? label ?? recognizedBy ?? keys.first ?? ""
    }

    /// The web domain or company number the issuer is recognized by, when there is one.
    public var recognizedBy: String? {
        keys.first { $0.contains(".") || $0.contains(where: \.isNumber) }
    }
}

/// A header line seen on past scans, kept as a fingerprint, with the issuers it was seen with.
public struct HeaderLine: Equatable, Sendable, Codable {
    public var fingerprint: String
    public var scans: Int
    /// Fingerprints of the domains and company identifiers of the documents it was on.
    public var issuers: [String]
    /// The owners of the documents it was on when they were sent, while there were several owners.
    public var owners: [UUID]

    public init(fingerprint: String, scans: Int = 0, issuers: [String] = [], owners: [UUID] = []) {
        self.fingerprint = fingerprint
        self.scans = scans
        self.issuers = issuers
        self.owners = owners
    }
}
