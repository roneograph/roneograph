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
    public var keepScans = ScanRetention.week

    public init() {}

    /// The built-in categories, then the user's, Other last.
    public var allCategories: [DocumentCategory] {
        DocumentCategory.builtIn.dropLast() + categories.sorted() + [.other]
    }

    /// The categories to pick from, with the current one even when the user removed it since.
    public func categories(keeping current: DocumentCategory) -> [DocumentCategory] {
        let all = allCategories
        return all.contains(current) ? all : all + [current]
    }

    public var hasValidEmail: Bool { Self.isValidEmail(email) }

    public static func isValidEmail(_ email: String) -> Bool {
        email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s.]{2,}/) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case email, archiveFolder, askedForEmail, dismissedPageTip, autoCapture, askForName, fileNameFormat, categories, learnedIssuers, headerLines, keepScans
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
        keepScans = (try? container.decode(ScanRetention.self, forKey: .keepScans)) ?? defaults.keepScans
    }
}

/// How long scans stay on the device before they are deleted, sent or not.
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

    public init(keys: [String], label: String? = nil, issuer: String? = nil, category: DocumentCategory? = nil, name: NamePattern? = nil) {
        self.keys = keys
        self.label = label
        self.issuer = issuer
        self.category = category
        self.name = name
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

    public init(fingerprint: String, scans: Int = 0, issuers: [String] = []) {
        self.fingerprint = fingerprint
        self.scans = scans
        self.issuers = issuers
    }
}
