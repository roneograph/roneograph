import UIKit
import XCTest

@MainActor
final class SendBarUITests: XCTestCase {
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

    func testSharesOnceThePDFIsMadeWhenTappedBefore() throws {
        let roneograph = Roneograph(photos: try photos())
        let app = roneograph.app
        roneograph.tap(app.buttons["Share"])
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: Roneograph.timeout), "The share sheet did not open once the PDF was made")
    }

    func testConnectsPaperlessFromTheFooter() throws {
        let roneograph = Roneograph(photos: try photos())
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
        let roneograph = Roneograph(photos: try photos())
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
