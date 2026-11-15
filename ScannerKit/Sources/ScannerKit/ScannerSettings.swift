import Foundation

public struct ScannerSettings: Equatable, Sendable, Codable {
    /// Recipient of the Email button; empty when not set.
    public var email = ""
    public var autoCapture = true
    /// Nil lets each page pick its look.
    public var look: PageLook?
    public var quality = PDFQuality.balanced
    public var paper = Paper.a4
    /// Opens the rename sheet when the review screen first shows.
    public var askForName = false
    public var fileNameFormat = FileNameFormat()
    public var keepDays = 7

    public init() {}

    public var hasValidEmail: Bool { Self.isValidEmail(email) }

    public static func isValidEmail(_ email: String) -> Bool {
        email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s.]{2,}/) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case email, autoCapture, look, quality, paper, askForName, fileNameFormat, keepDays
    }

    /// Missing or unknown values keep their default, so settings survive app updates.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScannerSettings()
        email = (try? container.decode(String.self, forKey: .email)) ?? defaults.email
        autoCapture = (try? container.decode(Bool.self, forKey: .autoCapture)) ?? defaults.autoCapture
        look = try? container.decode(PageLook.self, forKey: .look)
        quality = (try? container.decode(PDFQuality.self, forKey: .quality)) ?? defaults.quality
        paper = (try? container.decode(Paper.self, forKey: .paper)) ?? defaults.paper
        askForName = (try? container.decode(Bool.self, forKey: .askForName)) ?? defaults.askForName
        fileNameFormat = (try? container.decode(FileNameFormat.self, forKey: .fileNameFormat)) ?? defaults.fileNameFormat
        keepDays = (try? container.decode(Int.self, forKey: .keepDays)) ?? defaults.keepDays
    }
}
