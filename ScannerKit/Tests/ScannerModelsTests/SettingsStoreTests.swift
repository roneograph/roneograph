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

    @Test func showsThePageTipUntilDismissed() throws {
        let fixture = try Fixture()
        #expect(fixture.settings.showsPageTip)
        fixture.settings.dismissPageTip()
        #expect(!fixture.settings.showsPageTip)
        #expect(!SettingsStore(defaults: fixture.defaults).showsPageTip)
    }
}
