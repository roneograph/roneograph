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

    @Test func learnsCorrectionsByAnyKeyOfTheIssuerAndKeepsTheOthers() throws {
        let fixture = try Fixture()
        fixture.settings.learn(keys: ["lumen-energy.example", "lumen energie sas"]) { $0.issuer = "Lumen Energy" }
        #expect(fixture.settings.learnedIssuer(for: ["lumen energie sas"])?.issuer == "Lumen Energy")
        #expect(fixture.settings.learnedIssuer(for: ["other.example"]) == nil)
        #expect(fixture.settings.learnedIssuer(for: []) == nil)
        fixture.settings.learn(keys: ["lumen-energy.example"]) { $0.category = DocumentCategory("House") }
        #expect(fixture.settings.value.learnedIssuers.count == 1)
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
        fixture.settings.learn(keys: ["lumen"]) { $0.category = .invoice }
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
