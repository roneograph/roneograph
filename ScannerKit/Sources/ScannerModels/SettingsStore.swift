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
    static let learnedNamesLimit = 200

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

    public func learnedName(for suggestion: String) -> String? {
        value.learnedNames.first { $0.suggestion == suggestion }?.name
    }

    /// Remembers the name given instead of a suggestion; going back to the suggestion forgets it.
    public func learn(_ name: String, for suggestion: String) {
        var names = value.learnedNames.filter { $0.suggestion != suggestion }
        if name != suggestion { names.insert(LearnedName(suggestion: suggestion, name: name), at: 0) }
        value.learnedNames = Array(names.prefix(Self.learnedNamesLimit))
    }

    public var showsPageTip: Bool { !value.dismissedPageTip }

    public func dismissPageTip() {
        if !value.dismissedPageTip { value.dismissedPageTip = true }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(value), forKey: Self.key)
    }
}
