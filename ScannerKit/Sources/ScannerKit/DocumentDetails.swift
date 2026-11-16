import Foundation

/// What kind of document a scan is: one of the built-in categories, or one the user added.
public struct DocumentCategory: Hashable, Sendable, Codable, RawRepresentable, Comparable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ name: String) {
        rawValue = name
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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

    public var isBuiltIn: Bool { Self.builtIn.contains(self) }
}

/// The details of a document, detected from its text and editable by the user.
public struct DocumentDetails: Equatable, Sendable, Codable {
    /// Other when nothing better was found.
    public var category: DocumentCategory
    public var issuer: String?
    /// The date printed on the document.
    public var date: Date?
    /// The reference printed on the document: invoice, contract or policy number.
    public var number: String?

    public init(category: DocumentCategory = .other, issuer: String? = nil, date: Date? = nil, number: String? = nil) {
        self.category = category
        self.issuer = issuer
        self.date = date
        self.number = number
    }

    private enum CodingKeys: String, CodingKey {
        case category, issuer, date, number
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = (try? container.decode(DocumentCategory.self, forKey: .category)) ?? .other
        issuer = try? container.decode(String.self, forKey: .issuer)
        date = try? container.decode(Date.self, forKey: .date)
        number = try? container.decode(String.self, forKey: .number)
    }
}

/// The words of the name suggestions that come from details, as printed on the page, so a format showing these details can leave them out of the name.
public struct SuggestedParts: Equatable, Sendable, Codable {
    /// The word or heading that gave the category, such as "Facture".
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
    /// Fingerprints of the header lines that could have been the issuer, to learn which ones are the user's own name and address.
    public var headerLines: [String]

    public init(details: DocumentDetails = .init(), parts: SuggestedParts = .init(), issuerKeys: [String] = [], issuerEvidence: [String] = [], headerLines: [String] = []) {
        self.details = details
        self.parts = parts
        self.issuerKeys = issuerKeys
        self.issuerEvidence = issuerEvidence
        self.headerLines = headerLines
    }
}
