import UIKit
import XCTest

@MainActor
final class SendBarUITests: XCTestCase {
    private static let nothingToSendWith = """
        {"owners": [{"id": "6F1C2D3E-0000-4000-8000-000000000001", "name": "Personal", "showsSaveToFiles": false, "showsShare": false}]}
        """
    override func setUp() {
        continueAfterFailure = false
    }

    /// A folder holding one photo of a page, removed once the test is done.
    private func photos() throws -> URL {
        let photos = FileManager.default.temporaryDirectory.appending(path: "SendBarUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: photos) }
        try Self.photo().write(to: photos.appending(path: "page.jpg"))
        return photos
    }

    /// A sheet of paper with a few lines, on a dark table.
    private static func photo() -> Data {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 100, y: 100, width: 700, height: 990))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.black]
            for (index, line) in ["Lumen Energy", "Invoice 2026-118", "Total 42.00"].enumerated() {
                line.draw(at: CGPoint(x: 160, y: 180 + index * 60), withAttributes: attributes)
            }
        }
    }

    func testSetsUpSendingFromReview() throws {
        let roneograph = Roneograph(settings: Self.nothingToSendWith, photos: try photos())
        let app = roneograph.app
        roneograph.tap(app.buttons["Set Up Sending…"])
        let sheet = app.navigationBars["Sending for Personal"]
        XCTAssertTrue(sheet.waitForExistence(timeout: Roneograph.timeout))
        let share = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Share")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: Roneograph.timeout))
        share.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(sheet.isHittable, "Setting a way closed the sheet")
        roneograph.tap(sheet.buttons["Done"])
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: Roneograph.timeout))
        XCTAssertFalse(app.buttons["Set Up Sending…"].exists)
    }

    func testSetsUpEmailFromHomeInOneStep() throws {
        let roneograph = Roneograph(photos: try photos(), screen: "home")
        let app = roneograph.app
        roneograph.tap(app.buttons["Set Up"])
        let sheet = app.navigationBars["Sending for Me"]
        XCTAssertTrue(sheet.waitForExistence(timeout: Roneograph.timeout), "Sending for Me did not open")
        let email = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "you@example.com")).firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: Roneograph.timeout))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Roneograph.timeout), "The keyboard is not up")
        XCTAssertEqual(email.value(forKey: "hasKeyboardFocus") as? Bool, true, "The Email field has no focus")
        app.typeText("claire@example.com")
        XCTAssertEqual(email.value as? String, "claire@example.com")
        XCTAssertTrue(sheet.isHittable, "A valid address closed the sheet")
        roneograph.tap(sheet.buttons["Done"])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: Roneograph.timeout))
        XCTAssertFalse(app.buttons["Set Up"].exists, "The card is still on Home")
    }
}
