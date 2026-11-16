import Foundation

public struct ScannerSettings: Equatable, Sendable, Codable {
    /// Recipient of the Email button; empty when not set.
    public var email = ""
    /// Set once the first tap on Email asked for an address, answered or not.
    public var askedForEmail = false
    /// Set once the review screen tip about tapping pages was closed, or a page was opened.
    public var dismissedPageTip = false
    public var autoCapture = true
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
        case email, askedForEmail, dismissedPageTip, autoCapture, askForName, fileNameFormat, keepDays
    }

    /// Missing or unknown values keep their default, so settings survive app updates.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ScannerSettings()
        email = (try? container.decode(String.self, forKey: .email)) ?? defaults.email
        askedForEmail = (try? container.decode(Bool.self, forKey: .askedForEmail)) ?? defaults.askedForEmail
        dismissedPageTip = (try? container.decode(Bool.self, forKey: .dismissedPageTip)) ?? defaults.dismissedPageTip
        autoCapture = (try? container.decode(Bool.self, forKey: .autoCapture)) ?? defaults.autoCapture
        askForName = (try? container.decode(Bool.self, forKey: .askForName)) ?? defaults.askForName
        fileNameFormat = (try? container.decode(FileNameFormat.self, forKey: .fileNameFormat)) ?? defaults.fileNameFormat
        keepDays = (try? container.decode(Int.self, forKey: .keepDays)) ?? defaults.keepDays
    }
}
