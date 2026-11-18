import Foundation
import ScannerKit
@testable import ScannerModels
import Testing

@MainActor
@Suite(.serialized)
struct SettingsStoreTests {
    @Test(.timeLimit(.minutes(1)))
    func savesABurstOfChangesOnceTheyStop() async throws {
        let fixture = try Fixture()
        let defaults = try #require(CountingDefaults(suiteName: fixture.suite))
        let settings = SettingsStore(defaults: defaults, saveDelay: .milliseconds(20))
        for typed in ["F", "Fe", "Fern", "Fernwood"] { settings.value.defaultOwner.name = typed }
        #expect(defaults.writes == 0)

        while defaults.writes == 0 { try await Task.sleep(for: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(defaults.writes == 1)
        #expect(SettingsStore(defaults: defaults).value.defaultOwner.name == "Fernwood")
    }

    @Test func keepsSettingsItCannotReadInsteadOfLosingThem() throws {
        let fixture = try Fixture()
        let unreadable = Data(#"{"keepScans":"year"}"#.utf8)
        fixture.defaults.set(unreadable, forKey: "settings")
        let settings = SettingsStore(defaults: fixture.defaults)
        #expect(settings.value.keepScans == .week)
        settings.value.autoCapture = false
        settings.save()
        #expect(fixture.defaults.data(forKey: SettingsStore.unreadableKey) == unreadable)
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

    @Test func forgetsAllIssuers() throws {
        let fixture = try Fixture()
        fixture.settings.learn(keys: ["lumen"]) { $0.category = .invoice }
        fixture.settings.learn(keys: ["northwind"]) { $0.category = .insurance }
        fixture.settings.forgetAllIssuers()
        #expect(fixture.settings.value.learnedIssuers.isEmpty)
    }

    @Test func startsWithOneOwnerNamedMeThatIsTheDefault() throws {
        let fixture = try Fixture()
        let settings = fixture.settings.value
        #expect(settings.owners.map(\.name) == ["Me"])
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
        #expect(SettingsStore(defaults: fixture.defaults).value.owners.map(\.name) == ["Me", "Fernwood Holding"])
    }

    @Test func renamesOwnersOnlyToANameNoOtherOwnerHas() throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        #expect(!fixture.settings.renameOwner(holding.id, to: "  "))
        #expect(!fixture.settings.renameOwner(holding.id, to: " me "))
        #expect(fixture.settings.value.owner(holding.id).name == "Fernwood Holding")
        #expect(fixture.settings.renameOwner(holding.id, to: " fernwood holding "))
        #expect(fixture.settings.value.owner(holding.id).name == "fernwood holding")
        #expect(fixture.settings.renameOwner(holding.id, to: "Fernwood"))
        #expect(fixture.settings.value.owner(holding.id).name == "Fernwood")
    }

    @Test func setsTheOtherNamesOfAnOwnerAsTyped() throws {
        let fixture = try Fixture()
        let owner = fixture.settings.value.defaultOwnerID
        fixture.settings.setName(" Camille Delmas ", of: owner)
        fixture.settings.setName("Camille Delmas", of: owner)
        fixture.settings.setName("  ", of: owner)
        fixture.settings.setName("Camille Arnaud", of: owner)
        #expect(fixture.settings.value.owner(owner).names == ["Camille Delmas", "Camille Arnaud"])
        fixture.settings.setName("C. Arnaud", at: 1, of: owner)
        #expect(fixture.settings.value.owner(owner).names == ["Camille Delmas", "C. Arnaud"])
        fixture.settings.setName("", at: 0, of: owner)
        #expect(fixture.settings.value.owner(owner).names == ["C. Arnaud"])
    }

    @Test func setsTheAddressesOfAnOwnerLineByLine() throws {
        let fixture = try Fixture()
        let owner = fixture.settings.value.defaultOwnerID
        fixture.settings.setAddress(" 8 rue des Glycines \n\n 69007 Lyon\n", of: owner)
        fixture.settings.setAddress("3 impasse des Tilleuls 38000 Grenoble", of: owner)
        #expect(fixture.settings.value.owner(owner).addresses == ["8 rue des Glycines\n69007 Lyon", "3 impasse des Tilleuls 38000 Grenoble"])
        fixture.settings.setAddress(" \n ", at: 1, of: owner)
        #expect(fixture.settings.value.owner(owner).addresses == ["8 rue des Glycines\n69007 Lyon"])
        fixture.settings.save()
        #expect(SettingsStore(defaults: fixture.defaults).value.owner(owner).addresses == ["8 rue des Glycines\n69007 Lyon"])
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
        fixture.settings.learn(keys: ["print"]) { $0.owner = holding.id }
        fixture.settings.learn(keys: ["lumen"]) { $0.owner = holding.id; $0.category = .invoice }
        fixture.settings.removeOwner(holding.id)
        #expect(fixture.settings.learnedIssuer(for: ["print"]) == nil)
        #expect(fixture.settings.learnedIssuer(for: ["lumen"]) == LearnedIssuer(keys: ["lumen"], category: .invoice))
    }

    @Test func removingAnOwnerGivesWhatRecognizedItToTheOwnerOfItsScans() throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let employer = try #require(fixture.settings.addOwner("Halcyon Labs"))
        fixture.settings.learn(keys: ["print"]) { $0.owner = holding.id }
        fixture.settings.removeOwner(holding.id, movingTo: holding.id)
        #expect(fixture.settings.value.hasOwner(holding.id))

        fixture.settings.removeOwner(holding.id, movingTo: employer.id)
        #expect(fixture.settings.learnedIssuer(for: ["print"])?.owner == employer.id)
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

    @Test func addsCategoriesOnceBeforeOther() throws {
        let fixture = try Fixture()
        let car = fixture.settings.addCategory(" Car ")
        #expect(car == DocumentCategory("Car"))
        #expect(fixture.settings.addCategory("car") == car)
        #expect(fixture.settings.addCategory("invoice") == .invoice)
        #expect(fixture.settings.addCategory("  ") == nil)
        fixture.settings.addCategory("Apartment")
        #expect(fixture.settings.value.allCategories.contains(DocumentCategory("Apartment")))
        #expect(fixture.settings.value.allCategories.last == .other)
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
