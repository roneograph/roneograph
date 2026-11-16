import Foundation
import ScannerKit
import Testing

struct ScannerSettingsTests {
    @Test func keepsDefaultsForMissingOrUnknownValues() throws {
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(#"{"email":"me@example.com","keepScans":"huge"}"#.utf8))
        #expect(settings.email == "me@example.com")
        #expect(settings.keepScans == .week)
        #expect(settings.autoCapture)
    }

    @Test(arguments: ScanRetention.allCases)
    func keepsTheRetentionAcrossARestart(retention: ScanRetention) throws {
        var settings = ScannerSettings()
        settings.keepScans = retention
        let decoded = try JSONDecoder().decode(ScannerSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.keepScans == retention)
    }

    @Test func keepsTheCurrentCategoryEvenWhenRemoved() {
        var settings = ScannerSettings()
        settings.categories = [DocumentCategory("Car")]
        #expect(settings.categories(keeping: .invoice) == settings.allCategories)
        #expect(settings.categories(keeping: DocumentCategory("Car")) == settings.allCategories)
        #expect(settings.categories(keeping: DocumentCategory("Boat")) == settings.allCategories + [DocumentCategory("Boat")])
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
