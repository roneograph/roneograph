import Foundation
import Observation
import ScannerKit

@MainActor @Observable
public final class SettingsStore {
    public var value: ScannerSettings {
        didSet { scheduleSave() }
    }

    private let defaults: UserDefaults
    private let saveDelay: Duration
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// The app's own folder in Files, where scan PDFs are deleted with their scans.
    private let appFolder: URL?
    private static let key = "settings"
    /// Settings this build could not read, kept so they can be recovered instead of being replaced by the defaults.
    static let unreadableKey = "settings.unreadable"
    static let learnedIssuersLimit = 200
    static let headerLinesLimit = 500
    /// A header line seen this often, with documents from different issuers, is the user's own name or address.
    static let ownLineScans = 3

    public enum FolderError: LocalizedError {
        case insideApp

        public var errorDescription: String? {
            "Roneograph deletes the PDFs in its own folder with their scans. Choose a folder outside it."
        }
    }

    /// Changes are saved once they stop for `saveDelay`, or when `save()` is called.
    public init(defaults: UserDefaults = .standard, appFolder: URL? = nil, saveDelay: Duration = .milliseconds(500)) {
        self.defaults = defaults
        self.appFolder = appFolder
        self.saveDelay = saveDelay
        guard let data = defaults.data(forKey: Self.key) else {
            value = ScannerSettings()
            return
        }
        do {
            value = try JSONDecoder().decode(ScannerSettings.self, from: data)
        } catch {
            defaults.set(data, forKey: Self.unreadableKey)
            value = ScannerSettings()
        }
    }

    /// Remembers the folder picked in Files for the Save button of an owner; refuses the app's own folder.
    public func chooseArchiveFolder(_ url: URL, for ownerID: UUID?) throws {
        if let appFolder, url.resolvingSymlinksInPath().pathComponents.starts(with: appFolder.resolvingSymlinksInPath().pathComponents) {
            throw FolderError.insideApp
        }
        var owner = value.owner(ownerID)
        owner.archiveFolder = try ArchiveFolder(url: url)
        value.updateOwner(owner)
    }

    // MARK: Owners

    /// Adds an owner named as typed, with the file name format of the default owner; returns it, or the existing owner with the same name.
    @discardableResult
    public func addOwner(_ name: String) -> Owner? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = owner(named: name) { return existing }
        let owner = Owner(name: name, fileNameFormat: value.defaultOwner.fileNameFormat)
        value.addOwner(owner)
        return owner
    }

    /// Renames an owner as typed, trimmed; returns false, keeping its name, when the name is empty or another owner's.
    @discardableResult
    public func renameOwner(_ id: UUID, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, value.hasOwner(id), owner(named: name).map({ $0.id == id }) ?? true else { return false }
        var owner = value.owner(id)
        owner.name = name
        value.updateOwner(owner)
        return true
    }

    /// Adds another name of an owner, or replaces the one at `index`, trimmed; an empty name removes it, and a name it already has is not added twice.
    public func setName(_ name: String, at index: Int? = nil, of ownerID: UUID) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        update(\.names, of: ownerID, with: name, at: index)
    }

    /// Adds an address of an owner, or replaces the one at `index`, each line trimmed and blank lines left out; an empty address removes it.
    public func setAddress(_ address: String, at index: Int? = nil, of ownerID: UUID) {
        let address = address.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
        update(\.addresses, of: ownerID, with: address, at: index)
    }

    private func update(_ list: WritableKeyPath<Owner, [String]>, of ownerID: UUID, with text: String, at index: Int?) {
        guard value.hasOwner(ownerID) else { return }
        var owner = value.owner(ownerID)
        var items = owner[keyPath: list]
        let others = items.indices.filter { $0 != index }.map { items[$0] }
        if let index, items.indices.contains(index) {
            if text.isEmpty || others.contains(text) { items.remove(at: index) } else { items[index] = text }
        } else if !text.isEmpty, !items.contains(text) {
            items.append(text)
        }
        owner[keyPath: list] = items
        value.updateOwner(owner)
    }

    private func owner(named name: String) -> Owner? {
        value.owners.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Removes an owner, never the default one. Its issuers and lines go to the owner its scans moved to;
    /// without one, its issuers are forgotten and a line also seen with another owner keeps telling none.
    /// With a single owner left, no issuer remembers an owner.
    public func removeOwner(_ id: UUID, movingTo newOwner: UUID? = nil) {
        guard id != value.defaultOwnerID, newOwner.map({ $0 != id && value.hasOwner($0) }) ?? true else { return }
        var settings = value
        settings.removeOwner(id)
        for index in settings.learnedIssuers.indices where settings.learnedIssuers[index].owner == id || !settings.hasSeveralOwners {
            settings.learnedIssuers[index].owner = settings.hasSeveralOwners ? newOwner : nil
        }
        settings.learnedIssuers.removeAll(where: \.isEmpty)
        for index in settings.headerLines.indices where settings.headerLines[index].owners.contains(id) {
            let owners = settings.headerLines[index].owners
            if let newOwner {
                settings.headerLines[index].owners = owners.reduce(into: []) { kept, owner in
                    let owner = owner == id ? newOwner : owner
                    if !kept.contains(owner) { kept.append(owner) }
                }
            } else if owners == [id] {
                settings.headerLines[index].owners = []
            }
        }
        value = settings
    }

    /// The owner the lines of a page tell, from the documents sent before: a line counts once it was seen with documents from different issuers, all of one owner.
    /// Another owner wins over the default one, whose name also shows on the paper of a company; two other owners tell nothing.
    public func owner(recognizing fingerprints: [String]) -> UUID? {
        guard value.hasSeveralOwners, !fingerprints.isEmpty else { return nil }
        let found = Set(value.headerLines.filter { line in
            line.issuers.count >= 2 && line.owners.count == 1 && fingerprints.contains(line.fingerprint)
        }.compactMap(\.owners.first).filter(value.hasOwner))
        let others = found.subtracting([value.defaultOwnerID])
        if others.count == 1 { return others.first }
        return others.isEmpty ? found.first : nil
    }

    /// Links the header lines of a sent document to its owner, instead of the previous one when the owner of a sent document changed.
    /// A line seen with documents of several owners tells none of them.
    public func link(lines fingerprints: [String], to ownerID: UUID, replacing previous: UUID? = nil) {
        guard value.hasSeveralOwners, !fingerprints.isEmpty else { return }
        var lines = value.headerLines
        for index in lines.indices where fingerprints.contains(lines[index].fingerprint) {
            if let previous { lines[index].owners.removeAll { $0 == previous } }
            if !lines[index].owners.contains(ownerID) { lines[index].owners.append(ownerID) }
        }
        if lines != value.headerLines { value.headerLines = lines }
    }

    /// Whether the lines of some documents tell this owner.
    public func recognizesLines(of ownerID: UUID) -> Bool {
        value.headerLines.contains { $0.issuers.count >= 2 && $0.owners == [ownerID] }
    }

    /// How many issuers this owner is remembered for.
    public func issuerCount(of ownerID: UUID) -> Int {
        value.learnedIssuers.filter { $0.owner == ownerID }.count
    }

    /// What the user corrected on the last document recognized by one of these keys.
    public func learnedIssuer(for keys: [String]) -> LearnedIssuer? {
        guard !keys.isEmpty else { return nil }
        return value.learnedIssuers.first { $0.keys.contains(where: keys.contains) }
    }

    /// Remembers a correction for the next documents from the same issuer, keeping the other corrections made for it.
    /// `label` is the issuer of the corrected document, to show who this is.
    public func learn(keys: [String], label: String? = nil, _ change: (inout LearnedIssuer) -> Void) {
        guard !keys.isEmpty else { return }
        var learned = learnedIssuer(for: keys) ?? LearnedIssuer(keys: keys)
        learned.keys = keys
        if let label { learned.label = label }
        change(&learned)
        var issuers = value.learnedIssuers.filter { !$0.keys.contains(where: keys.contains) }
        if !learned.isEmpty { issuers.insert(learned, at: 0) }
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

    /// Forgets some of the corrections for an issuer, keeping the others.
    public func forget(_ values: Set<RememberedValue>, keys: [String]) {
        guard learnedIssuer(for: keys) != nil else { return }
        learn(keys: keys) { learned in
            if values.contains(.name) { learned.name = nil }
            if values.contains(.category) { learned.category = nil }
            if values.contains(.issuer) { learned.issuer = nil }
            if values.contains(.owner) { learned.owner = nil }
        }
    }

    public func forget(_ issuer: LearnedIssuer) {
        value.learnedIssuers.removeAll { $0.keys == issuer.keys }
    }

    public func forgetAllIssuers() {
        value.learnedIssuers = []
    }

    /// Whether some lines are known to be the user's own name and address.
    public var recognizesOwnLines: Bool { !ownLines.isEmpty }

    public var hasLearned: Bool {
        !value.learnedIssuers.isEmpty || !value.headerLines.isEmpty
    }

    /// Forgets the corrections for every issuer and which lines are the user's own.
    public func forgetEverything() {
        value.learnedIssuers = []
        value.headerLines = []
    }

    /// Adds a category of the user's; returns it, or the existing category with the same name.
    @discardableResult
    public func addCategory(_ name: String) -> DocumentCategory? {
        let name = FileNamer.finalName(name, fallback: "")
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

    /// Saving encodes every setting, learned issuers and header lines included, so a burst of changes such as typing is saved once.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Saves the changes not saved yet, as when the app leaves the foreground, where it can be stopped at any time.
    public func save() {
        guard let pendingSave else { return }
        pendingSave.cancel()
        self.pendingSave = nil
        defaults.set(try? JSONEncoder().encode(value), forKey: Self.key)
    }
}
