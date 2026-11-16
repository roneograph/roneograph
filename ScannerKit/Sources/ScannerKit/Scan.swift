import Foundation

public struct ScanPage: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    /// Where the page is in the original photo, nil when the whole photo is the page.
    public var quad: Quad?
    /// Where the page was found when it was captured, to go back to it after a manual crop.
    public var detectedQuad: Quad?
    public var analysis: PageAnalysis
    public var cleanup: CleanupSettings
    /// Bumped on every change, so cached images are reloaded.
    public var revision: Int

    public init(id: UUID = UUID(), quad: Quad?, analysis: PageAnalysis, cleanup: CleanupSettings = .init(), revision: Int = 0) {
        self.id = id
        self.quad = quad
        self.detectedQuad = quad
        self.analysis = analysis
        self.cleanup = cleanup
        self.revision = revision
    }

    public var look: PageLook { cleanup.look ?? analysis.suggestedLook }

    /// Turns the page a quarter turn.
    public mutating func rotate(clockwise: Bool) {
        analysis.orientation = analysis.orientation.turned(clockwise: clockwise)
        revision += 1
    }
}

public enum SendMethod: String, Equatable, Sendable, Codable {
    case email, share
}

public struct Scan: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var created: Date
    /// File name of the PDF, without the extension, from `title` and the file name format.
    public var name: String
    /// The name as people read it: shown in the app and used as the email subject.
    public var title: String
    /// The date printed on the document, used by file name formats with a date.
    public var documentDate: Date?
    /// True once the user renamed the scan; suggestions then stop replacing the name.
    public var isNamedByUser = false
    public var suggestions: [String] = []
    public var pages: [ScanPage] = []
    /// False while pages are being captured.
    public var isFinished = false
    public var sent: Date?
    public var sentBy: SendMethod?

    public init(id: UUID = UUID(), created: Date = .now, name: String, title: String? = nil) {
        self.id = id
        self.created = created
        self.name = name
        self.title = title ?? name
    }

    /// The date a file name format puts first.
    public var fileDate: Date { documentDate ?? created }
}
