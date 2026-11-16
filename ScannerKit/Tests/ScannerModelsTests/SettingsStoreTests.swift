import Foundation
import ScannerKit
@testable import ScannerModels
import Testing

@MainActor
@Suite(.serialized)
struct SettingsStoreTests {
    @Test func asksForAnEmailOnlyWhenNoneIsSet() throws {
        let fixture = try Fixture()
        #expect(fixture.settings.shouldAskForEmail)
        fixture.settings.value.email = "me@example.com"
        #expect(!fixture.settings.shouldAskForEmail)
    }

    @Test func keepsTheAnsweredEmailAndStopsAsking() throws {
        let fixture = try Fixture()
        fixture.settings.answerEmailQuestion(" me@example.com ")
        #expect(fixture.settings.value.email == "me@example.com")
        #expect(!SettingsStore(defaults: fixture.defaults).shouldAskForEmail)
    }

    @Test(arguments: ["", "me@example"])
    func stopsAskingWhenDeclinedOrInvalid(answer: String) throws {
        let fixture = try Fixture()
        fixture.settings.answerEmailQuestion(answer)
        #expect(fixture.settings.value.email == "")
        #expect(!fixture.settings.shouldAskForEmail)
    }

    @Test func learnsCorrectedNamesMostRecentFirstAndKeepsThem() throws {
        let fixture = try Fixture()
        fixture.settings.learn("Lumen Energy", for: "Invoice LUMEN ENERGIE")
        fixture.settings.learn("Water bill", for: "Facture Eau de Paris")
        fixture.settings.learn("Lumen", for: "Invoice LUMEN ENERGIE")
        #expect(fixture.settings.value.learnedNames.map(\.name) == ["Lumen", "Water bill"])
        #expect(SettingsStore(defaults: fixture.defaults).learnedName(for: "Invoice LUMEN ENERGIE") == "Lumen")
    }

    @Test func forgetsANameWhenTheSuggestionIsChosenAgain() throws {
        let fixture = try Fixture()
        fixture.settings.learn("Lumen", for: "Invoice Lumen")
        fixture.settings.learn("Invoice Lumen", for: "Invoice Lumen")
        #expect(fixture.settings.learnedName(for: "Invoice Lumen") == nil)
    }

    @Test func keepsALimitedNumberOfLearnedNames() throws {
        let fixture = try Fixture()
        for index in 0...SettingsStore.learnedNamesLimit {
            fixture.settings.learn("Name \(index)", for: "Suggestion \(index)")
        }
        #expect(fixture.settings.value.learnedNames.count == SettingsStore.learnedNamesLimit)
        #expect(fixture.settings.learnedName(for: "Suggestion 0") == nil)
    }

    @Test func learnsAnIssuerByAnyOfItsKeys() throws {
        let fixture = try Fixture()
        fixture.settings.learnIssuer("Lumen Energy", category: .invoice, keys: ["lumen-energy.example", "lumen energie sas"])
        #expect(fixture.settings.learnedIssuer(for: ["lumen energie sas"])?.issuer == "Lumen Energy")
        #expect(fixture.settings.learnedIssuer(for: ["other.example"]) == nil)
        #expect(fixture.settings.learnedIssuer(for: []) == nil)
        fixture.settings.learnIssuer("Lumen", category: DocumentCategory("House"), keys: ["lumen-energy.example"])
        #expect(fixture.settings.value.learnedIssuers.count == 1)
        #expect(SettingsStore(defaults: fixture.defaults).learnedIssuer(for: ["lumen-energy.example"]) == LearnedIssuer(keys: ["lumen-energy.example"], issuer: "Lumen", category: DocumentCategory("House")))
    }

    @Test func learnsNothingWithoutAKey() throws {
        let fixture = try Fixture()
        fixture.settings.learnIssuer("Lumen", category: .invoice, keys: [])
        #expect(fixture.settings.value.learnedIssuers.isEmpty)
    }

    @Test func recognizesTheUsersOwnLinesOnDocumentsFromDifferentIssuers() throws {
        let fixture = try Fixture()
        fixture.settings.recordHeaderLines(["me", "street", "lumen"], issuerEvidence: ["lumen-energy.example"])
        fixture.settings.recordHeaderLines(["me", "street", "bank"], issuerEvidence: ["bank.example"])
        #expect(fixture.settings.ownLines.isEmpty)
        fixture.settings.recordHeaderLines(["me", "street", "lumen"], issuerEvidence: ["lumen-energy.example"])
        #expect(fixture.settings.ownLines == ["me", "street"])
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

    @Test func forgetsEverythingLearned() throws {
        let fixture = try Fixture()
        fixture.settings.learn("Lumen", for: "Invoice Lumen")
        fixture.settings.learnIssuer("Lumen", category: .invoice, keys: ["lumen"])
        fixture.settings.recordHeaderLines(["me"], issuerEvidence: [])
        #expect(fixture.settings.hasLearned)
        fixture.settings.forgetLearned()
        #expect(!fixture.settings.hasLearned)
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
        #expect(SettingsStore(defaults: fixture.defaults).value.categories == [DocumentCategory("Apartment")])
    }

    @Test func showsThePageTipUntilDismissed() throws {
        let fixture = try Fixture()
        #expect(fixture.settings.showsPageTip)
        fixture.settings.dismissPageTip()
        #expect(!fixture.settings.showsPageTip)
        #expect(!SettingsStore(defaults: fixture.defaults).showsPageTip)
    }
}
