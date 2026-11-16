import Foundation
import Observation
import ScannerKit

@MainActor @Observable
public final class SettingsStore {
    public var value: ScannerSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private static let key = "settings"
    static let learnedIssuersLimit = 200
    static let headerLinesLimit = 500
    /// A header line seen this often, with documents from different issuers, is the user's own name or address.
    static let ownLineScans = 3

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ScannerSettings.self, from: $0) } ?? ScannerSettings()
    }

    /// The first tap on Email asks where scans go, unless an address is already set.
    public var shouldAskForEmail: Bool { !value.hasValidEmail && !value.askedForEmail }

    /// Keeps the address when it is valid; either way, the question is not asked again.
    public func answerEmailQuestion(_ email: String) {
        let email = email.trimmingCharacters(in: .whitespaces)
        if ScannerSettings.isValidEmail(email) { value.email = email }
        value.askedForEmail = true
    }

    /// Remembers the folder picked in Files for the Save button.
    public func chooseArchiveFolder(_ url: URL) throws {
        value.archiveFolder = try ArchiveFolder(url: url)
    }

    /// What the user corrected on the last document recognized by one of these keys.
    public func learnedIssuer(for keys: [String]) -> LearnedIssuer? {
        guard !keys.isEmpty else { return nil }
        return value.learnedIssuers.first { $0.keys.contains(where: keys.contains) }
    }

    /// Remembers a correction for the next documents from the same issuer, keeping the other corrections made for it.
    public func learn(keys: [String], _ change: (inout LearnedIssuer) -> Void) {
        guard !keys.isEmpty else { return }
        var learned = learnedIssuer(for: keys) ?? LearnedIssuer(keys: keys)
        learned.keys = keys
        change(&learned)
        var issuers = value.learnedIssuers.filter { !$0.keys.contains(where: keys.contains) }
        if learned.issuer != nil || learned.category != nil || learned.name != nil { issuers.insert(learned, at: 0) }
        value.learnedIssuers = Array(issuers.prefix(Self.learnedIssuersLimit))
    }

    /// Fingerprints of the lines that keep coming back on documents from different issuers: the user's own name and address.
    public var ownLines: Set<String> {
        Set(value.headerLines.filter { $0.scans >= Self.ownLineScans && $0.issuers.count >= 2 }.map(\.fingerprint))
    }

    /// Counts the header lines of a new document, with the domains and identifiers that tell its issuer apart.
    public func recordHeaderLines(_ fingerprints: [String], issuerEvidence: [String]) {
        guard !fingerprints.isEmpty else { return }
        let issuer = issuerEvidence.first.map(DocumentDetector.fingerprint)
        var lines = value.headerLines
        for fingerprint in Set(fingerprints) {
            var line = lines.first { $0.fingerprint == fingerprint } ?? HeaderLine(fingerprint: fingerprint)
            lines.removeAll { $0.fingerprint == fingerprint }
            line.scans += 1
            if let issuer, !line.issuers.contains(issuer) { line.issuers = Array((line.issuers + [issuer]).suffix(4)) }
            lines.insert(line, at: 0)
        }
        value.headerLines = Array(lines.prefix(Self.headerLinesLimit))
    }

    public var hasLearned: Bool {
        !value.learnedIssuers.isEmpty || !value.headerLines.isEmpty
    }

    public func forgetLearned() {
        value.learnedIssuers = []
        value.headerLines = []
    }

    /// Adds a category of the user's; returns it, or the existing category with the same name.
    @discardableResult
    public func addCategory(_ name: String) -> DocumentCategory? {
        let name = FileNamer().finalName(name, fallback: "")
        guard !name.isEmpty else { return nil }
        if let existing = value.allCategories.first(where: { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }) { return existing }
        let category = DocumentCategory(name)
        value.categories.append(category)
        return category
    }

    public func removeCategory(_ category: DocumentCategory) {
        value.categories.removeAll { $0 == category }
    }

    public var showsPageTip: Bool { !value.dismissedPageTip }

    public func dismissPageTip() {
        if !value.dismissedPageTip { value.dismissedPageTip = true }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(value), forKey: Self.key)
    }
}
