import Foundation
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

    @Test func showsThePageTipUntilDismissed() throws {
        let fixture = try Fixture()
        #expect(fixture.settings.showsPageTip)
        fixture.settings.dismissPageTip()
        #expect(!fixture.settings.showsPageTip)
        #expect(!SettingsStore(defaults: fixture.defaults).showsPageTip)
    }
}
