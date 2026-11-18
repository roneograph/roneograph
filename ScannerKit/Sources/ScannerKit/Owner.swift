import Foundation

/// Whose documents are: the user, a company they run or work for. Each owner has its own Paperless server and file names.
public struct Owner: Identifiable, Equatable, Sendable, Codable {
    /// How its names are printed on mail: a company with a legal form, a person with a title or initials.
    public enum Kind: String, CaseIterable, Sendable, Codable {
        case person, company

        /// Also reads the symbols older builds saved: a house is a person, a building or a briefcase a company.
        init?(saved: String) {
            switch saved {
            case "person", "house": self = .person
            case "company", "building", "briefcase": self = .company
            default: return nil
            }
        }
    }

    public let id: UUID
    public var name: String
    public var kind: Kind
    /// Where the Archive button sends PDFs; nil until a server is connected.
    public var paperless: PaperlessServer?
    public var fileNameFormat = FileNameFormat()
    /// Other names its mail is addressed to, such as a maiden name; its own name always is one.
    public var names: [String] = []
    /// The addresses its mail is sent to, as typed, possibly on several lines.
    public var addresses: [String] = []

    /// The name of the default owner of a new install, until the user types theirs; it tells no page.
    public static let placeholderName = "Me"

    public init(id: UUID = UUID(), name: String, kind: Kind = .company, fileNameFormat: FileNameFormat = FileNameFormat()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.fileNameFormat = fileNameFormat
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decode(UUID.self, forKey: .id), name: container.decode(String.self, forKey: .name))
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        if let saved = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? (try? legacy.decodeIfPresent(String.self, forKey: .symbol)), let kind = Kind(saved: saved) {
            self.kind = kind
        }
        paperless = try container.decode(.paperless, or: paperless)
        fileNameFormat = try container.decode(.fileNameFormat, or: fileNameFormat)
        names = try container.decode(.names, or: names)
        addresses = try container.decode(.addresses, or: addresses)
    }

    /// Keys older builds saved under another name.
    private enum LegacyKeys: String, CodingKey {
        case symbol
    }

    public var hasPlaceholderName: Bool { name == Self.placeholderName }
}
