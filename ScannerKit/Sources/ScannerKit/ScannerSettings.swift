import Foundation

public struct ScannerSettings: Equatable, Sendable, Codable {
    /// Recipient of the Email button; empty when not set.
    public var email = ""
    /// Where the Save button puts PDFs; nil until a folder is picked.
    public var archiveFolder: ArchiveFolder?
    /// Set once the first tap on Email asked for an address, answered or not.
    public var askedForEmail = false
    /// Set once the review screen tip about tapping pages was closed, or a page was opened.
    public var dismissedPageTip = false
    public var autoCapture = true
    /// Opens the rename sheet when the review screen first shows.
    public var askForName = false
    public var fileNameFormat = FileNameFormat()
    /// Categories the user added to the built-in ones.
    public var categories: [DocumentCategory] = []
    /// The issuer, category and name the user gave to documents from an issuer, most recent first.
    public var learnedIssuers: [LearnedIssuer] = []
    /// Header lines seen on past scans, to recognize the user's own name and address.
    public var headerLines: [HeaderLine] = []
    public var keepDays = 7

    public init() {}

    /// The built-in categories, then the user's, Other last.
    public var allCategories: [DocumentCategory] {
        DocumentCategory.builtIn.dropLast() + categories.sorted() + [.other]
    }

    public var hasValidEmail: Bool { Self.isValidEmail(email) }

    public static func isValidEmail(_ email: String) -> Bool {
        email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s.]{2,}/) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case email, archiveFolder, askedForEmail, dismissedPageTip, autoCapture, askForName, fileNameFormat, categories, learnedIssuers, headerLines, keepDays
    }

    /// Missing or unknown values keep their default, so settings survive app updates.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScannerSettings()
        email = (try? container.decode(String.self, forKey: .email)) ?? defaults.email
        archiveFolder = try? container.decode(ArchiveFolder.self, forKey: .archiveFolder)
        askedForEmail = (try? container.decode(Bool.self, forKey: .askedForEmail)) ?? defaults.askedForEmail
        dismissedPageTip = (try? container.decode(Bool.self, forKey: .dismissedPageTip)) ?? defaults.dismissedPageTip
        autoCapture = (try? container.decode(Bool.self, forKey: .autoCapture)) ?? defaults.autoCapture
        askForName = (try? container.decode(Bool.self, forKey: .askForName)) ?? defaults.askForName
        fileNameFormat = (try? container.decode(FileNameFormat.self, forKey: .fileNameFormat)) ?? defaults.fileNameFormat
        categories = (try? container.decode([DocumentCategory].self, forKey: .categories)) ?? defaults.categories
        learnedIssuers = (try? container.decode([LearnedIssuer].self, forKey: .learnedIssuers)) ?? defaults.learnedIssuers
        headerLines = (try? container.decode([HeaderLine].self, forKey: .headerLines)) ?? defaults.headerLines
        keepDays = (try? container.decode(Int.self, forKey: .keepDays)) ?? defaults.keepDays
    }
}

/// What the user corrected on documents from one issuer, recognized by any of its keys; nil when not corrected.
public struct LearnedIssuer: Equatable, Sendable, Codable {
    public var keys: [String]
    public var issuer: String?
    public var category: DocumentCategory?
    public var name: NamePattern?

    public init(keys: [String], issuer: String? = nil, category: DocumentCategory? = nil, name: NamePattern? = nil) {
        self.keys = keys
        self.issuer = issuer
        self.category = category
        self.name = name
    }
}

/// A header line seen on past scans, kept as a fingerprint, with the issuers it was seen with.
public struct HeaderLine: Equatable, Sendable, Codable {
    public var fingerprint: String
    public var scans: Int
    /// Fingerprints of the domains and company identifiers of the documents it was on.
    public var issuers: [String]

    public init(fingerprint: String, scans: Int = 0, issuers: [String] = []) {
        self.fingerprint = fingerprint
        self.scans = scans
        self.issuers = issuers
    }
}
