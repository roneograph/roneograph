import Foundation

public struct ScanPage: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    /// Where the page is in the original photo, nil when the whole photo is the page.
    public var quad: Quad?
    public var analysis: PageAnalysis
    public var cleanup: CleanupSettings
    /// Bumped on every change, so cached images are reloaded.
    public var revision: Int

    public init(id: UUID = UUID(), quad: Quad?, analysis: PageAnalysis, cleanup: CleanupSettings = .init(), revision: Int = 0) {
        self.id = id
        self.quad = quad
        self.analysis = analysis
        self.cleanup = cleanup
        self.revision = revision
    }

    public var look: PageLook { cleanup.look ?? analysis.suggestedLook }

    /// Turns the page a quarter turn.
    public mutating func rotate(clockwise: Bool) {
        let order: [PageOrientation] = [.up, .right, .down, .left]
        let index = order.firstIndex(of: analysis.orientation)!
        analysis.orientation = order[(index + (clockwise ? 1 : 3)) % 4]
        revision += 1
    }
}

public struct Scan: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var created: Date
    public var name: String
    /// True once the user renamed the scan; suggestions then stop replacing the name.
    public var isNamedByUser = false
    public var suggestions: [String] = []
    public var pages: [ScanPage] = []
    /// Overrides the PDF size from the settings for this scan.
    public var quality: PDFQuality?
    /// False while pages are being captured.
    public var isFinished = false
    public var sent: Date?

    public init(id: UUID = UUID(), created: Date = .now, name: String) {
        self.id = id
        self.created = created
        self.name = name
    }
}
