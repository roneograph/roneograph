import Foundation

public struct ScannerSettings: Equatable, Sendable, Codable {
    /// Never empty; with a single owner, the app never mentions owners.
    public private(set) var owners: [Owner]
    /// The owner of the documents nothing on the page tells the owner of.
    public var defaultOwnerID: UUID {
        didSet { if !owners.contains(where: { $0.id == defaultOwnerID }) { defaultOwnerID = oldValue } }
    }
    public var autoCapture = true
    /// Document types the user added to the built-in ones.
    public var documentTypes: [DocumentType] = []
    /// The issuer, document type, name and owner the user gave to documents from an issuer, most recent first.
    public var learnedIssuers: [LearnedIssuer] = []

    public init() {
        let me = Owner(name: Owner.placeholderName, symbol: .person)
        owners = [me]
        defaultOwnerID = me.id
    }

    /// Settings saved by an older build keep their values; the keys added since take their defaults.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let owners = try container.decode(.owners, or: owners)
        if !owners.isEmpty { self.owners = owners }
        let defaultOwnerID = try container.decode(.defaultOwnerID, or: self.owners[0].id)
        self.defaultOwnerID = hasOwner(defaultOwnerID) ? defaultOwnerID : self.owners[0].id
        autoCapture = try container.decode(.autoCapture, or: autoCapture)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        documentTypes = try container.decode(.documentTypes, or: legacy.decode(.categories, or: documentTypes))
        learnedIssuers = try container.decode(.learnedIssuers, or: learnedIssuers)
    }

    /// Keys older builds saved under another name.
    private enum LegacyKeys: String, CodingKey {
        case categories
    }

    public var hasSeveralOwners: Bool { owners.count > 1 }

    /// Tells the owner of a page from the names and addresses of the owners, as they are now.
    public var ownerMatcher: OwnerMatcher { OwnerMatcher(owners: owners, defaultOwnerID: defaultOwnerID) }

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

    /// The built-in document types and the user's in alphabetical order, Other last.
    public var allDocumentTypes: [DocumentType] {
        DocumentType.alphabetical(DocumentType.builtIn + documentTypes)
    }

    /// The document types to pick from, with the current one even when the user removed it since.
    public func documentTypes(keeping current: DocumentType) -> [DocumentType] {
        let all = allDocumentTypes
        return all.contains(current) ? all : DocumentType.alphabetical(all + [current])
    }
}

/// What the user corrected on documents from one issuer, recognized by any of its keys; nil when not corrected.
public struct LearnedIssuer: Equatable, Sendable, Codable {
    public var keys: [String]
    /// The issuer of the last corrected document, to show who this is.
    public var label: String?
    public var issuer: String?
    public var documentType: DocumentType?
    public var name: NamePattern?
    public var owner: UUID?

    public init(keys: [String], label: String? = nil, issuer: String? = nil, documentType: DocumentType? = nil, name: NamePattern? = nil, owner: UUID? = nil) {
        self.keys = keys
        self.label = label
        self.issuer = issuer
        self.documentType = documentType
        self.name = name
        self.owner = owner
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        try self.init(
            keys: container.decode([String].self, forKey: .keys),
            label: container.decodeIfPresent(String.self, forKey: .label),
            issuer: container.decodeIfPresent(String.self, forKey: .issuer),
            documentType: container.decodeIfPresent(DocumentType.self, forKey: .documentType) ?? legacy.decodeIfPresent(DocumentType.self, forKey: .category),
            name: container.decodeIfPresent(NamePattern.self, forKey: .name),
            owner: container.decodeIfPresent(UUID.self, forKey: .owner)
        )
    }

    /// Keys older builds saved under another name.
    private enum LegacyKeys: String, CodingKey {
        case category
    }

    /// Whether anything is left to reuse for the next documents.
    public var isEmpty: Bool {
        issuer == nil && documentType == nil && name == nil && owner == nil
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
