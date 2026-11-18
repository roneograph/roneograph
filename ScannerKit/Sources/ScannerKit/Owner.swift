import Foundation

/// Whose documents are: the user, a company they run or work for. Each owner has its own Paperless server and file names.
public struct Owner: Identifiable, Equatable, Sendable, Codable {
    public enum Symbol: String, CaseIterable, Sendable, Codable {
        case person, house, building, briefcase
    }

    public let id: UUID
    public var name: String
    public var symbol: Symbol
    /// Where the Archive button sends PDFs; nil until a server is connected.
    public var paperless: PaperlessServer?
    public var fileNameFormat = FileNameFormat()
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
        paperless = try container.decode(.paperless, or: paperless)
        fileNameFormat = try container.decode(.fileNameFormat, or: fileNameFormat)
        names = try container.decode(.names, or: names)
        addresses = try container.decode(.addresses, or: addresses)
    }

    public var hasPlaceholderName: Bool { name == Self.placeholderName }
}
