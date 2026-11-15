import Foundation
import ScannerKit
import Testing

struct ScannerSettingsTests {
    @Test func keepsDefaultsForMissingOrUnknownValues() throws {
        let settings = try JSONDecoder().decode(ScannerSettings.self, from: Data(#"{"email":"me@example.com","quality":"huge"}"#.utf8))
        #expect(settings.email == "me@example.com")
        #expect(settings.quality == .balanced)
        #expect(settings.paper == .a4)
        #expect(settings.autoCapture)
    }

    @Test(arguments: [("me@example.com", true), ("me@example", false), ("", false), ("a b@example.com", false), ("me@example.c", false)])
    func validatesEmails(email: String, valid: Bool) {
        #expect(ScannerSettings.isValidEmail(email) == valid)
    }
}
