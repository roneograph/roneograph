import Foundation

/// Whose documents are: the user, a company they run or work for. Each owner has its own destinations and file names.
public struct Owner: Identifiable, Equatable, Sendable, Codable {
    public enum Symbol: String, CaseIterable, Sendable, Codable {
        case person, house, building, briefcase
    }

    public let id: UUID
    public var name: String
    public var symbol: Symbol
    /// Recipient of the Email button; empty when not set.
    public var email = ""
    /// Where the Save button puts PDFs; nil until a folder is picked.
    public var archiveFolder: ArchiveFolder?
    /// Where the Archive button sends PDFs; nil until a server is connected.
    public var paperless: PaperlessServer?
    public var fileNameFormat = FileNameFormat()
    /// Whether the send bar has Save to Files and Share for this owner's documents; Archive and Email show once it has a server or an address.
    public var showsSaveToFiles = true
    public var showsShare = true
    /// Other names its mail is addressed to, such as a maiden name; its own name always is one.
    public var names: [String] = []
    /// The addresses its mail is sent to, as typed, possibly on several lines.
    public var addresses: [String] = []

    /// The name of the default owner of a new install, until the user types theirs; it tells no page.
    public static let placeholderName = "Me"

    public init(id: UUID = UUID(), name: String, symbol: Symbol = .building, fileNameFormat: FileNameFormat = FileNameFormat()) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.fileNameFormat = fileNameFormat
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decode(UUID.self, forKey: .id), name: container.decode(String.self, forKey: .name))
        symbol = try container.decode(.symbol, or: symbol)
        email = try container.decode(.email, or: email)
        archiveFolder = try container.decode(.archiveFolder, or: archiveFolder)
        paperless = try container.decode(.paperless, or: paperless)
        fileNameFormat = try container.decode(.fileNameFormat, or: fileNameFormat)
        showsSaveToFiles = try container.decode(.showsSaveToFiles, or: showsSaveToFiles)
        showsShare = try container.decode(.showsShare, or: showsShare)
        names = try container.decode(.names, or: names)
        addresses = try container.decode(.addresses, or: addresses)
    }

    public var hasValidEmail: Bool { ScannerSettings.isValidEmail(email) }

    public var hasPlaceholderName: Bool { name == Self.placeholderName }
}
