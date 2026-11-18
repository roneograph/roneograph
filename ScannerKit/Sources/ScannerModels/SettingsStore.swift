import Foundation
import Observation
import ScannerKit

@MainActor @Observable
public final class SettingsStore {
    public var value: ScannerSettings {
        didSet {
            scheduleSave()
            let changed = value.owners.filter { owner in oldValue.owners.contains { $0.id == owner.id && $0.fileNameFormat != owner.fileNameFormat } }
            if !changed.isEmpty { didChangeFileNameFormat?(Set(changed.map(\.id))) }
        }
    }
    /// Called with the owners whose file name format changed.
    @ObservationIgnored var didChangeFileNameFormat: ((Set<UUID>) -> Void)?

    private let defaults: UserDefaults
    private let saveDelay: Duration
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    private static let key = "settings"
    /// Settings this build could not read, kept so they can be recovered instead of being replaced by the defaults.
    static let unreadableKey = "settings.unreadable"
    static let learnedIssuersLimit = 200

    /// Changes are saved once they stop for `saveDelay`, or when `save()` is called.
    public init(defaults: UserDefaults = .standard, saveDelay: Duration = .milliseconds(500)) {
        self.defaults = defaults
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

    /// Whether settings this build could not read are kept aside, so what they refer to, such as Paperless tokens, must be kept too.
    public var hasUnreadableSettings: Bool {
        defaults.data(forKey: Self.unreadableKey) != nil
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

    /// Removes an owner, never the default one. Its issuers go to the owner its scans moved to; without one, they are forgotten.
    /// With a single owner left, no issuer remembers an owner.
    public func removeOwner(_ id: UUID, movingTo newOwner: UUID? = nil) {
        guard id != value.defaultOwnerID, newOwner.map({ $0 != id && value.hasOwner($0) }) ?? true else { return }
        var settings = value
        settings.removeOwner(id)
        for index in settings.learnedIssuers.indices where settings.learnedIssuers[index].owner == id || !settings.hasSeveralOwners {
            settings.learnedIssuers[index].owner = settings.hasSeveralOwners ? newOwner : nil
        }
        settings.learnedIssuers.removeAll(where: \.isEmpty)
        value = settings
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

    /// Forgets some of the corrections for an issuer, keeping the others.
    public func forget(_ values: Set<RememberedValue>, keys: [String]) {
        guard learnedIssuer(for: keys) != nil else { return }
        learn(keys: keys) { learned in
            if values.contains(.name) { learned.name = nil }
            if values.contains(.documentType) { learned.documentType = nil }
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


    /// Adds a document type of the user's; returns it, or the existing document type with the same name.
    @discardableResult
    public func addDocumentType(_ name: String) -> DocumentType? {
        let name = FileNamer.finalName(name, fallback: "")
        guard !name.isEmpty else { return nil }
        if let existing = value.allDocumentTypes.first(where: { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }) { return existing }
        let documentType = DocumentType(name)
        value.documentTypes.append(documentType)
        return documentType
    }

    public func removeDocumentType(_ documentType: DocumentType) {
        value.documentTypes.removeAll { $0 == documentType }
    }

    /// Saving encodes every setting, learned issuers included, so a burst of changes such as typing is saved once.
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
