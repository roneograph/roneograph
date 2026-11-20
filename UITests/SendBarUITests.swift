import XCTest

@MainActor
final class SendBarUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSharesOnceThePDFIsMadeWhenTappedBefore() throws {
        let roneograph = Roneograph(photos: try pagePhotos())
        let app = roneograph.app
        roneograph.tap(app.buttons["Share"])
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: Roneograph.timeout), "The share sheet did not open once the PDF was made")
    }

    func testConnectsPaperlessFromTheFooter() throws {
        let roneograph = Roneograph(photos: try pagePhotos())
        let app = roneograph.app
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: Roneograph.timeout))
        XCTAssertFalse(app.buttons["Archive"].exists, "Archive needs a Paperless server")
        roneograph.tap(app.buttons["Connect Paperless"])
        let sheet = app.navigationBars["Paperless for Me"]
        XCTAssertTrue(sheet.waitForExistence(timeout: Roneograph.timeout), "Paperless for Me did not open")
        roneograph.tap(sheet.buttons["Cancel"])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: Roneograph.timeout))
    }

    func testShowsTheCommentOfTheScan() throws {
        let roneograph = Roneograph(photos: try pagePhotos())
        let app = roneograph.app
        roneograph.tap(app.buttons["Add Comment"])
        let sheet = app.navigationBars["Comment"]
        XCTAssertTrue(sheet.waitForExistence(timeout: Roneograph.timeout), "The Comment sheet did not open")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Roneograph.timeout), "The keyboard is not up")
        app.typeText("Lunch with Ada and Linus")
        roneograph.tap(sheet.buttons["Done"])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: Roneograph.timeout))
        XCTAssertTrue(app.buttons["Comment, Lunch with Ada and Linus"].waitForExistence(timeout: Roneograph.timeout), "The comment is not shown")
        XCTAssertFalse(app.buttons["Add Comment"].exists)
    }
}
