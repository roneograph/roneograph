import Foundation

/// What kind of document a scan is: one of the built-in document types, or one the user added.
public struct DocumentType: Hashable, Sendable, Codable, RawRepresentable, Comparable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ name: String) {
        rawValue = name
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.localizedStandardCompare(rhs.rawValue) == .orderedAscending
    }

    public static let invoice = Self("Invoice")
    public static let receipt = Self("Receipt")
    public static let quote = Self("Quote")
    public static let contract = Self("Contract")
    public static let payslip = Self("Payslip")
    public static let bankStatement = Self("Bank statement")
    public static let taxNotice = Self("Tax notice")
    public static let insurance = Self("Insurance")
    public static let medical = Self("Medical")
    public static let certificate = Self("Certificate")
    public static let letter = Self("Letter")
    public static let other = Self("Other")

    public static let builtIn: [Self] = [.invoice, .receipt, .quote, .contract, .payslip, .bankStatement, .taxNotice, .insurance, .medical, .certificate, .letter, .other]

    /// The document types sorted by name, Other last.
    public static func alphabetical(_ documentTypes: [Self]) -> [Self] {
        let sorted = documentTypes.filter { $0 != .other }.sorted()
        return documentTypes.contains(.other) ? sorted + [.other] : sorted
    }
}

/// The details of a document, detected from its text and editable by the user.
public struct DocumentDetails: Equatable, Sendable, Codable {
    /// Other when nothing better was found.
    public var documentType: DocumentType
    public var issuer: String?
    /// The date printed on the document.
    public var date: Date?
    /// The reference printed on the document: invoice, contract or policy number.
    public var number: String?

    public init(documentType: DocumentType = .other, issuer: String? = nil, date: Date? = nil, number: String? = nil) {
        self.documentType = documentType
        self.issuer = issuer
        self.date = date
        self.number = number
    }
}

/// The words of the name suggestions that come from details, as printed on the page, so a format showing these details can leave them out of the name.
public struct SuggestedParts: Equatable, Sendable, Codable {
    /// The word or heading that gave the document type, such as "Facture".
    public var type: String?
    public var issuer: String?
    public var number: String?

    public init(type: String? = nil, issuer: String? = nil, number: String? = nil) {
        self.type = type
        self.issuer = issuer
        self.number = number
    }
}

/// Everything read on the first page of a document.
public struct DetectedDocument: Equatable, Sendable {
    public var details: DocumentDetails
    public var parts: SuggestedParts
    /// Stable ways to recognize the issuer on the next document: web or email domains, company identifiers, then the folded issuer name.
    public var issuerKeys: [String]
    /// Domains and company identifiers only, which tell issuers apart better than names.
    public var issuerEvidence: [String]
    /// The owner the page is addressed to, from its name or address on the page.
    public var owner: RecognizedOwner?

    public init(details: DocumentDetails = .init(), parts: SuggestedParts = .init(), issuerKeys: [String] = [], issuerEvidence: [String] = [], owner: RecognizedOwner? = nil) {
        self.details = details
        self.parts = parts
        self.issuerKeys = issuerKeys
        self.issuerEvidence = issuerEvidence
        self.owner = owner
    }
}
