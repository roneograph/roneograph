import Foundation
import ScannerKit
import Testing

struct ScannerSettingsTests {
    @Test(arguments: [(ScanRetention.day, "day"), (.week, "week"), (.month, "month"), (.forever, "forever")])
    func keepsTheRetentionAcrossARestart(retention: ScanRetention, stored: String) throws {
        var settings = ScannerSettings()
        settings.keepScans = retention
        let json = try JSONEncoder().encode(settings)
        #expect(String(decoding: json, as: UTF8.self).contains(#""keepScans":"\#(stored)""#))
        #expect(try JSONDecoder().decode(ScannerSettings.self, from: json).keepScans == retention)
    }

    @Test func readsSettingsSavedBeforeKeysWereAdded() throws {
        let json = #"{"owners":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Fernwood Holding","email":"accounting@fernwood.example"}],"askForName":true}"#
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(json.utf8))
        #expect(settings.defaultOwner.name == "Fernwood Holding")
        #expect(settings.defaultOwner.email == "accounting@fernwood.example")
        #expect(settings.defaultOwner.fileNameFormat == FileNameFormat())
        #expect(settings.askForName)
        #expect(settings.defaultOwner.showsSaveToFiles)
        #expect(settings.defaultOwner.showsShare)
        #expect(settings.keepScans == .week)
    }

    @Test func givesEachOwnerTheSendBarSavedForAllOwners() throws {
        let json = #"""
            {"owners":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Personal"},{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3302","name":"Fernwood Holding","showsShare":true}],"showsSaveToFiles":false,"showsShare":false}
            """#
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(json.utf8))
        #expect(settings.owners.map(\.showsSaveToFiles) == [false, false])
        #expect(settings.owners.map(\.showsShare) == [false, true])
        let saved = try JSONEncoder().encode(settings)
        let keys = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any]).keys
        #expect(!keys.contains("showsSaveToFiles") && !keys.contains("showsShare"))
        #expect(try JSONDecoder().decode(ScannerSettings.self, from: saved) == settings)
    }

    @Test func keepsTheDefaultOwnerAmongTheOwners() throws {
        let json = #"{"owners":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Personal"}],"defaultOwnerID":"3F2504E0-4F89-11D3-9A0C-0305E82C3302"}"#
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(json.utf8))
        #expect(settings.defaultOwnerID == settings.owners[0].id)
        #expect(try JSONDecoder().decode(ScannerSettings.self, from: Data("{}".utf8)).owners.count == 1)
    }

    @Test func refusesAValueItCannotRead() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ScannerSettings.self, from: Data(#"{"keepScans":"year"}"#.utf8)) }
    }

    /// Guards the hand-written decoders: a setting added without being decoded would be lost at each launch.
    @Test func readsBackEverySetting() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ScannerSettingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let format = FileNameFormat(datePosition: .start, dateStyle: .month, dateSource: .scan, separator: .dash, lowercase: true, isCustom: true, template: "{ISSUER}")
        var owner = Owner(name: "Fernwood Holding", symbol: .briefcase, fileNameFormat: format)
        owner.email = "accounting@fernwood.example"
        owner.archiveFolder = try ArchiveFolder(url: root)
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!, storagePath: PaperlessStoragePath(id: 7, name: "Fernwood"))
        owner.showsSaveToFiles = false
        owner.showsShare = false
        var settings = ScannerSettings()
        settings.addOwner(owner)
        settings.defaultOwnerID = owner.id
        settings.dismissedPageTip = true
        settings.autoCapture = false
        settings.askForName = true
        settings.categories = [DocumentCategory("Car")]
        settings.learnedIssuers = [LearnedIssuer(keys: ["lumen"], issuer: "Lumen Energy")]
        settings.headerLines = [HeaderLine(fingerprint: "abc", scans: 2)]
        settings.keepScans = .forever
        settings.dismissedSendSetup = true

        expectEveryPropertyChanged(settings, from: ScannerSettings())
        expectEveryPropertyChanged(owner, from: Owner(id: owner.id, name: owner.name))
        expectEveryPropertyChanged(format, from: FileNameFormat())
        #expect(try JSONDecoder().decode(ScannerSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    private func expectEveryPropertyChanged<T>(_ value: T, from original: T, sourceLocation: SourceLocation = #_sourceLocation) {
        let originals = Dictionary(uniqueKeysWithValues: Mirror(reflecting: original).children.map { ($0.label ?? "", String(describing: $0.value)) })
        for child in Mirror(reflecting: value).children where !["id", "name"].contains(child.label) {
            #expect(String(describing: child.value) != originals[child.label ?? ""], "Set \(child.label ?? "") to a value other than its default", sourceLocation: sourceLocation)
        }
    }

    @Test func listsCategoriesAlphabeticallyWithOtherLast() {
        var settings = ScannerSettings()
        settings.categories = [DocumentCategory("Car"), DocumentCategory("Apartment")]
        let names = settings.allCategories.map(\.rawValue)
        #expect(names == ["Apartment", "Bank statement", "Car", "Certificate", "Contract", "Insurance", "Invoice", "Letter", "Medical", "Payslip", "Quote", "Receipt", "Tax notice", "Other"])
    }

    @Test func keepsTheCurrentCategoryEvenWhenRemoved() {
        var settings = ScannerSettings()
        settings.categories = [DocumentCategory("Car")]
        #expect(settings.categories(keeping: .invoice) == settings.allCategories)
        #expect(settings.categories(keeping: DocumentCategory("Car")) == settings.allCategories)
        let kept = settings.categories(keeping: DocumentCategory("Boat"))
        #expect(kept == DocumentCategory.alphabetical(settings.allCategories + [DocumentCategory("Boat")]))
        #expect(kept[1] == DocumentCategory("Boat"))
    }

    @Test(arguments: [("me@example.com", true), ("me@example", false), ("", false), ("a b@example.com", false), ("me@example.c", false)])
    func validatesEmails(email: String, valid: Bool) {
        #expect(ScannerSettings.isValidEmail(email) == valid)
    }

    @Test(arguments: [
        (LearnedIssuer(keys: ["lumen.example", "lumen"], issuer: "Lumen Energy"), "Lumen Energy"),
        (LearnedIssuer(keys: ["lumen.example", "lumen"], label: "Lumen"), "Lumen"),
        (LearnedIssuer(keys: ["lumen", "FR12123456789"]), "FR12123456789"),
    ])
    func namesALearnedIssuer(issuer: LearnedIssuer, title: String) {
        #expect(issuer.title == title)
    }
}
