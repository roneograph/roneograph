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
    /// Set once the first tap on Email asked for an address, answered or not.
    public var askedForEmail = false
    /// Where the Save button puts PDFs; nil until a folder is picked.
    public var archiveFolder: ArchiveFolder?
    public var fileNameFormat = FileNameFormat()

    public init(id: UUID = UUID(), name: String, symbol: Symbol = .building, fileNameFormat: FileNameFormat = FileNameFormat()) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.fileNameFormat = fileNameFormat
    }

    public var hasValidEmail: Bool { ScannerSettings.isValidEmail(email) }
}
