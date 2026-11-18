import Foundation
import ScannerKit
import Testing

struct ScannerSettingsTests {
    @Test func readsSettingsSavedBeforeKeysWereAdded() throws {
        let json = #"{"owners":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Fernwood Holding"}]}"#
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(json.utf8))
        #expect(settings.defaultOwner.name == "Fernwood Holding")
        #expect(settings.defaultOwner.fileNameFormat == FileNameFormat())
        #expect(settings.defaultOwner.names.isEmpty)
        #expect(settings.defaultOwner.addresses.isEmpty)
    }

    @Test func ignoresTheSettingsOlderBuildsHad() throws {
        let json = #"""
            {"owners":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Fernwood Holding","email":"accounting@fernwood.example","archiveFolder":{"bookmark":"AAAA","name":"Paperwork"},"showsSaveToFiles":false,"showsShare":false,"paperless":{"url":"https://paperless.example.com/"}}],"showsSaveToFiles":false,"showsShare":false,"keepScans":"forever","dismissedSendSetup":true}
            """#
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(json.utf8))
        #expect(settings.defaultOwner.name == "Fernwood Holding")
        #expect(settings.defaultOwner.paperless?.url == URL(string: "https://paperless.example.com/"))
        let saved = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        for key in ["email", "archiveFolder", "showsSaveToFiles", "showsShare", "keepScans", "dismissedSendSetup"] { #expect(!saved.contains(key)) }
    }

    @Test func keepsOnlyTheFileNameOfACustomFormatSavedWithFolders() throws {
        let json = #"{"owners":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Personal","fileNameFormat":{"isCustom":true,"template":"{CATEGORY}/{YYYY}-{MM} {ISSUER}"}}]}"#
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(json.utf8))
        #expect(settings.defaultOwner.fileNameFormat == FileNameFormat(isCustom: true, template: "{YYYY}-{MM} {ISSUER}"))
    }

    @Test func ignoresTheHeaderLinesOfOlderBuilds() throws {
        let json = #"{"autoCapture":false,"headerLines":[{"fingerprint":"0a1b2c3d4e5f6071","scans":3,"issuers":["lumen"],"owners":[]}]}"#
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(json.utf8))
        #expect(!settings.autoCapture)
        #expect(!String(decoding: try JSONEncoder().encode(settings), as: UTF8.self).contains("headerLines"))
    }

    @Test func keepsTheDefaultOwnerAmongTheOwners() throws {
        let json = #"{"owners":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Personal"}],"defaultOwnerID":"3F2504E0-4F89-11D3-9A0C-0305E82C3302"}"#
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(json.utf8))
        #expect(settings.defaultOwnerID == settings.owners[0].id)
        #expect(try JSONDecoder().decode(ScannerSettings.self, from: Data("{}".utf8)).owners.count == 1)
    }

    @Test func refusesAValueItCannotRead() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ScannerSettings.self, from: Data(#"{"autoCapture":"sometimes"}"#.utf8)) }
    }

    /// Guards the hand-written decoders: a setting added without being decoded would be lost at each launch.
    @Test func readsBackEverySetting() throws {
        let format = FileNameFormat(datePosition: .start, dateStyle: .month, dateSource: .scan, separator: .dash, lowercase: true, isCustom: true, template: "{ISSUER}")
        var owner = Owner(name: "Fernwood Holding", symbol: .briefcase, fileNameFormat: format)
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!, storagePath: PaperlessStoragePath(id: 7, name: "Fernwood"))
        owner.names = ["Fernwood"]
        owner.addresses = ["8 rue des Glycines\n69007 Lyon"]
        var settings = ScannerSettings()
        settings.addOwner(owner)
        settings.defaultOwnerID = owner.id
        settings.dismissedPageTip = true
        settings.autoCapture = false
        settings.categories = [DocumentCategory("Car")]
        settings.learnedIssuers = [LearnedIssuer(keys: ["lumen"], issuer: "Lumen Energy")]

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

    @Test(arguments: [
        (LearnedIssuer(keys: ["lumen.example", "lumen"], issuer: "Lumen Energy"), "Lumen Energy"),
        (LearnedIssuer(keys: ["lumen.example", "lumen"], label: "Lumen"), "Lumen"),
        (LearnedIssuer(keys: ["lumen", "FR12123456789"]), "FR12123456789"),
    ])
    func namesALearnedIssuer(issuer: LearnedIssuer, title: String) {
        #expect(issuer.title == title)
    }
}
