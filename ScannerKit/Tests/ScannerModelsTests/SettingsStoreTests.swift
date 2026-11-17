import Foundation
import ScannerKit
@testable import ScannerModels
import Testing

@MainActor
@Suite(.serialized)
struct SettingsStoreTests {
    @Test(arguments: ["", "Invoice"])
    func refusesTheAppsOwnFolderForSaveToFiles(subfolder: String) throws {
        let fixture = try Fixture()
        let folder = fixture.store.documentsDirectory.appending(path: subfolder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(throws: SettingsStore.FolderError.insideApp) { try fixture.settings.chooseArchiveFolder(folder, for: nil) }
        #expect(fixture.settings.value.defaultOwner.archiveFolder == nil)
    }

    @Test func acceptsAFolderNextToTheAppsOwnFolder() throws {
        let fixture = try Fixture()
        let folder = fixture.root.appending(path: "Documents archive", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try fixture.settings.chooseArchiveFolder(folder, for: nil)
        #expect(fixture.settings.value.defaultOwner.archiveFolder?.name == "Documents archive")
    }

    @Test(.timeLimit(.minutes(1)))
    func savesABurstOfChangesOnceTheyStop() async throws {
        let fixture = try Fixture()
        let defaults = try #require(CountingDefaults(suiteName: fixture.suite))
        let settings = SettingsStore(defaults: defaults, saveDelay: .milliseconds(20))
        for typed in ["m", "me", "me@", "me@example.com"] { settings.value.defaultOwner.email = typed }
        #expect(defaults.writes == 0)

        while defaults.writes == 0 { try await Task.sleep(for: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(defaults.writes == 1)
        #expect(SettingsStore(defaults: defaults).value.defaultOwner.email == "me@example.com")
    }

    @Test func savingWithoutChangesWritesNothing() throws {
        let fixture = try Fixture()
        let defaults = try #require(CountingDefaults(suiteName: fixture.suite))
        let settings = SettingsStore(defaults: defaults, saveDelay: .seconds(3600))
        settings.save()
        #expect(defaults.writes == 0)
        settings.dismissPageTip()
        settings.save()
        settings.save()
        #expect(defaults.writes == 1)
    }

    @Test func asksForAnEmailOnlyWhenNoneIsSet() throws {
        let fixture = try Fixture()
        #expect(fixture.settings.shouldAskForEmail(for: nil))
        fixture.settings.value.defaultOwner.email = "me@example.com"
        #expect(!fixture.settings.shouldAskForEmail(for: nil))
    }

    @Test func keepsTheAnsweredEmailAndStopsAsking() throws {
        let fixture = try Fixture()
        fixture.settings.answerEmailQuestion(" me@example.com ", for: nil)
        #expect(fixture.settings.value.defaultOwner.email == "me@example.com")
        fixture.settings.save()
        #expect(!SettingsStore(defaults: fixture.defaults).shouldAskForEmail(for: nil))
    }

    @Test(arguments: ["", "me@example"])
    func stopsAskingWhenDeclinedOrInvalid(answer: String) throws {
        let fixture = try Fixture()
        fixture.settings.answerEmailQuestion(answer, for: nil)
        #expect(fixture.settings.value.defaultOwner.email == "")
        #expect(!fixture.settings.shouldAskForEmail(for: nil))
    }

    @Test func learnsCorrectionsByAnyKeyOfTheIssuerAndKeepsTheOthers() throws {
        let fixture = try Fixture()
        fixture.settings.learn(keys: ["lumen-energy.example", "lumen energie sas"]) { $0.issuer = "Lumen Energy" }
        #expect(fixture.settings.learnedIssuer(for: ["lumen energie sas"])?.issuer == "Lumen Energy")
        #expect(fixture.settings.learnedIssuer(for: ["other.example"]) == nil)
        #expect(fixture.settings.learnedIssuer(for: []) == nil)
        fixture.settings.learn(keys: ["lumen-energy.example"]) { $0.category = DocumentCategory("House") }
        #expect(fixture.settings.value.learnedIssuers.count == 1)
        fixture.settings.save()
        #expect(SettingsStore(defaults: fixture.defaults).learnedIssuer(for: ["lumen-energy.example"]) == LearnedIssuer(keys: ["lumen-energy.example"], issuer: "Lumen Energy", category: DocumentCategory("House")))
    }

    @Test func forgetsAnIssuerWhenNothingIsLeftToReuse() throws {
        let fixture = try Fixture()
        fixture.settings.learn(keys: ["lumen"]) { $0.name = NamePattern(name: "Lumen bill", details: .init(), date: .now) }
        fixture.settings.learn(keys: ["lumen"]) { $0.name = nil }
        #expect(fixture.settings.value.learnedIssuers.isEmpty)
    }

    @Test func learnsNothingWithoutAKey() throws {
        let fixture = try Fixture()
        fixture.settings.learn(keys: []) { $0.issuer = "Lumen" }
        #expect(fixture.settings.value.learnedIssuers.isEmpty)
    }

    @Test func keepsALimitedNumberOfIssuersMostRecentFirst() throws {
        let fixture = try Fixture()
        for index in 0...SettingsStore.learnedIssuersLimit {
            fixture.settings.learn(keys: ["issuer \(index)"]) { $0.category = .invoice }
        }
        #expect(fixture.settings.value.learnedIssuers.count == SettingsStore.learnedIssuersLimit)
        #expect(fixture.settings.value.learnedIssuers.first?.keys == ["issuer \(SettingsStore.learnedIssuersLimit)"])
        #expect(fixture.settings.learnedIssuer(for: ["issuer 0"]) == nil)
    }

    @Test func recognizesTheUsersOwnLinesOnDocumentsFromDifferentIssuers() throws {
        let fixture = try Fixture()
        fixture.settings.recordHeaderLines(["me", "street", "lumen"], issuerEvidence: ["lumen-energy.example"])
        fixture.settings.recordHeaderLines(["me", "street", "bank"], issuerEvidence: ["bank.example"])
        #expect(fixture.settings.ownLines.isEmpty)
        fixture.settings.recordHeaderLines(["me", "street", "lumen"], issuerEvidence: ["lumen-energy.example"])
        #expect(fixture.settings.ownLines == ["me", "street"])
        fixture.settings.save()
        #expect(SettingsStore(defaults: fixture.defaults).ownLines == ["me", "street"])
    }

    @Test func aRecurringIssuerIsNotTheUsersOwn() throws {
        let fixture = try Fixture()
        for _ in 0..<5 {
            fixture.settings.recordHeaderLines(["me", "lumen"], issuerEvidence: ["lumen-energy.example"])
            fixture.settings.recordHeaderLines(["me", "anonymous"], issuerEvidence: [])
        }
        #expect(fixture.settings.ownLines.isEmpty)
    }

    @Test func forgetsSomeCorrectionsOfAnIssuerAndKeepsTheOthers() throws {
        let fixture = try Fixture()
        fixture.settings.learn(keys: ["lumen"], label: "Lumen") { $0.category = .invoice; $0.issuer = "Lumen Energy" }
        fixture.settings.forget([.issuer], keys: ["lumen"])
        #expect(fixture.settings.learnedIssuer(for: ["lumen"]) == LearnedIssuer(keys: ["lumen"], label: "Lumen", category: .invoice))
        fixture.settings.forget([.category], keys: ["lumen"])
        #expect(fixture.settings.learnedIssuer(for: ["lumen"]) == nil)
    }

    @Test func forgetsOneIssuer() throws {
        let fixture = try Fixture()
        fixture.settings.learn(keys: ["lumen"]) { $0.category = .invoice }
        fixture.settings.learn(keys: ["northwind"]) { $0.category = .insurance }
        fixture.settings.forget(try #require(fixture.settings.learnedIssuer(for: ["lumen"])))
        #expect(fixture.settings.value.learnedIssuers.map(\.keys) == [["northwind"]])
    }

    @Test func forgetsEverythingLearned() throws {
        let fixture = try Fixture()
        fixture.settings.learn(keys: ["lumen"]) { $0.category = .invoice }
        fixture.settings.recordHeaderLines(["me"], issuerEvidence: [])
        #expect(fixture.settings.hasLearned)
        fixture.settings.forgetEverything()
        #expect(!fixture.settings.hasLearned)
    }

    @Test func startsWithOnePersonalOwnerThatIsTheDefault() throws {
        let fixture = try Fixture()
        let settings = fixture.settings.value
        #expect(settings.owners.map(\.name) == ["Personal"])
        #expect(settings.defaultOwner.id == settings.owners[0].id)
        #expect(!settings.hasSeveralOwners)
    }

    @Test func addsOwnersOnceWithTheFormatOfTheDefaultOwner() throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.fileNameFormat = FileNameFormat(separator: .dash)
        let holding = try #require(fixture.settings.addOwner(" Fernwood Holding "))
        #expect(holding.name == "Fernwood Holding")
        #expect(holding.fileNameFormat == FileNameFormat(separator: .dash))
        #expect(fixture.settings.addOwner("fernwood holding")?.id == holding.id)
        #expect(fixture.settings.addOwner("  ") == nil)
        fixture.settings.save()
        #expect(SettingsStore(defaults: fixture.defaults).value.owners.map(\.name) == ["Personal", "Fernwood Holding"])
    }

    @Test func renamesOwnersOnlyToANameNoOtherOwnerHas() throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        #expect(!fixture.settings.renameOwner(holding.id, to: "  "))
        #expect(!fixture.settings.renameOwner(holding.id, to: " personal "))
        #expect(fixture.settings.value.owner(holding.id).name == "Fernwood Holding")
        #expect(fixture.settings.renameOwner(holding.id, to: " fernwood holding "))
        #expect(fixture.settings.value.owner(holding.id).name == "fernwood holding")
        #expect(fixture.settings.renameOwner(holding.id, to: "Fernwood"))
        #expect(fixture.settings.value.owner(holding.id).name == "Fernwood")
    }

    @Test func asksForTheEmailOfEachOwner() throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        fixture.settings.answerEmailQuestion("accounting@fernwood.example", for: holding.id)
        #expect(fixture.settings.value.owner(holding.id).email == "accounting@fernwood.example")
        #expect(!fixture.settings.shouldAskForEmail(for: holding.id))
        #expect(fixture.settings.shouldAskForEmail(for: nil))
    }

    @Test func neverRemovesTheDefaultOwner() throws {
        let fixture = try Fixture()
        let personal = fixture.settings.value.defaultOwnerID
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        fixture.settings.removeOwner(personal)
        #expect(fixture.settings.value.owners.count == 2)
        fixture.settings.value.defaultOwnerID = UUID()
        #expect(fixture.settings.value.defaultOwnerID == personal)
        fixture.settings.value.defaultOwnerID = holding.id
        fixture.settings.removeOwner(personal)
        #expect(fixture.settings.value.owners.map(\.id) == [holding.id])
    }

    @Test func removingAnOwnerForgetsWhatRecognizedIt() throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let personal = fixture.settings.value.defaultOwnerID
        fixture.settings.learn(keys: ["print"]) { $0.owner = holding.id }
        fixture.settings.learn(keys: ["lumen"]) { $0.owner = holding.id; $0.category = .invoice }
        fixture.settings.value.headerLines = [
            HeaderLine(fingerprint: "street", issuers: ["print", "bank"], owners: [personal, holding.id]),
            HeaderLine(fingerprint: "fernwood holding", issuers: ["print", "bank"], owners: [holding.id]),
        ]
        fixture.settings.removeOwner(holding.id)
        #expect(fixture.settings.learnedIssuer(for: ["print"]) == nil)
        #expect(fixture.settings.learnedIssuer(for: ["lumen"]) == LearnedIssuer(keys: ["lumen"], category: .invoice))
        #expect(fixture.settings.value.headerLines.map(\.owners) == [[personal, holding.id], []])
        #expect(fixture.settings.owner(recognizing: ["street"]) == nil)
    }

    @Test func removingAnOwnerGivesWhatRecognizedItToTheOwnerOfItsScans() throws {
        let fixture = try Fixture()
        let personal = fixture.settings.value.defaultOwnerID
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let employer = try #require(fixture.settings.addOwner("Halcyon Labs"))
        fixture.settings.learn(keys: ["print"]) { $0.owner = holding.id }
        fixture.settings.value.headerLines = [
            HeaderLine(fingerprint: "street", issuers: ["print", "bank"], owners: [personal, holding.id]),
            HeaderLine(fingerprint: "both", issuers: ["print", "bank"], owners: [holding.id, employer.id]),
        ]
        fixture.settings.removeOwner(holding.id, movingTo: holding.id)
        #expect(fixture.settings.value.hasOwner(holding.id))

        fixture.settings.removeOwner(holding.id, movingTo: employer.id)
        #expect(fixture.settings.learnedIssuer(for: ["print"])?.owner == employer.id)
        #expect(fixture.settings.value.headerLines.map(\.owners) == [[personal, employer.id], [employer.id]])
        #expect(fixture.settings.owner(recognizing: ["street"]) == nil)
        #expect(fixture.settings.owner(recognizing: ["both"]) == employer.id)
    }

    @Test func forgetsTheOwnersOfIssuersWhenOneOwnerIsLeft() throws {
        let fixture = try Fixture()
        let personal = fixture.settings.value.defaultOwnerID
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        fixture.settings.learn(keys: ["print"]) { $0.owner = personal }
        fixture.settings.learn(keys: ["lumen"]) { $0.owner = personal; $0.category = .invoice }
        fixture.settings.learn(keys: ["bank"]) { $0.owner = holding.id }
        fixture.settings.removeOwner(holding.id, movingTo: personal)
        #expect(fixture.settings.value.learnedIssuers == [LearnedIssuer(keys: ["lumen"], category: .invoice)])
    }

    /// Lines seen with documents from two issuers, as the address block of an owner.
    private func recordAddressBlock(_ lines: [String], in settings: SettingsStore) {
        settings.recordHeaderLines(lines + ["print"], issuerEvidence: ["print.example"])
        settings.recordHeaderLines(lines + ["bank"], issuerEvidence: ["bank.example"])
    }

    @Test func recognizesAnOwnerByTheLinesOnlyItsDocumentsHad() throws {
        let fixture = try Fixture()
        let personal = fixture.settings.value.defaultOwnerID
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        recordAddressBlock(["fernwood holding", "street"], in: fixture.settings)
        recordAddressBlock(["alex martin", "street"], in: fixture.settings)
        fixture.settings.link(lines: ["fernwood holding", "street", "print"], to: holding.id)
        fixture.settings.link(lines: ["alex martin", "street", "bank"], to: personal)

        #expect(fixture.settings.owner(recognizing: ["fernwood holding", "street", "lumen"]) == holding.id)
        #expect(fixture.settings.owner(recognizing: ["alex martin", "street"]) == personal)
        #expect(fixture.settings.owner(recognizing: ["street", "print"]) == nil)
        #expect(fixture.settings.owner(recognizing: ["alex martin", "fernwood holding"]) == holding.id)
        #expect(fixture.settings.recognizesLines(of: holding.id))
    }

    @Test func twoOtherOwnersTellNothing() throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let employer = try #require(fixture.settings.addOwner("Halcyon Labs"))
        recordAddressBlock(["fernwood holding", "halcyon labs"], in: fixture.settings)
        fixture.settings.link(lines: ["fernwood holding"], to: holding.id)
        fixture.settings.link(lines: ["halcyon labs"], to: employer.id)
        #expect(fixture.settings.owner(recognizing: ["fernwood holding", "halcyon labs"]) == nil)
    }

    @Test func linksNothingWithASingleOwner() throws {
        let fixture = try Fixture()
        recordAddressBlock(["alex martin"], in: fixture.settings)
        fixture.settings.link(lines: ["alex martin"], to: fixture.settings.value.defaultOwnerID)
        #expect(fixture.settings.value.headerLines.allSatisfy { $0.owners.isEmpty })
        #expect(fixture.settings.owner(recognizing: ["alex martin"]) == nil)
    }

    @Test func addsCategoriesOnceBeforeOther() throws {
        let fixture = try Fixture()
        let car = fixture.settings.addCategory(" Car ")
        #expect(car == DocumentCategory("Car"))
        #expect(fixture.settings.addCategory("car") == car)
        #expect(fixture.settings.addCategory("invoice") == .invoice)
        #expect(fixture.settings.addCategory("  ") == nil)
        fixture.settings.addCategory("Apartment")
        #expect(fixture.settings.value.allCategories.suffix(3) == [DocumentCategory("Apartment"), DocumentCategory("Car"), .other])
        fixture.settings.removeCategory(DocumentCategory("Car"))
        fixture.settings.save()
        #expect(SettingsStore(defaults: fixture.defaults).value.categories == [DocumentCategory("Apartment")])
    }

    @Test func showsThePageTipUntilDismissed() throws {
        let fixture = try Fixture()
        #expect(fixture.settings.showsPageTip)
        fixture.settings.dismissPageTip()
        #expect(!fixture.settings.showsPageTip)
        fixture.settings.save()
        #expect(!SettingsStore(defaults: fixture.defaults).showsPageTip)
    }
}

private final class CountingDefaults: UserDefaults, @unchecked Sendable {
    private(set) var writes = 0

    override func set(_ value: Any?, forKey key: String) {
        writes += 1
        super.set(value, forKey: key)
    }
}
