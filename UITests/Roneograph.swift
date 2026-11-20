import UIKit
import XCTest

/// The app, launched with fresh settings and no scans, and the steps the tests share.
@MainActor
struct Roneograph {
    let app = XCUIApplication()
    static let timeout: TimeInterval = 10

    /// `settings` is the JSON of the settings to start from; the keys left out take their defaults.
    /// `photos` is a folder of JPEG photos scanned at launch into a scan, which opens for review.
    /// `screen` is the screen to open on launch instead: home, review or settings.
    /// `paperless` connects the owners with a server to one listing these names, as {"correspondents": ["Lumen"], "document_types": ["Invoice"]}.
    init(settings: String? = nil, photos: URL? = nil, screen: String? = nil, paperless: String? = nil) {
        app.launchEnvironment["RONEOGRAPH_UI_TESTING"] = "1"
        if let settings { app.launchEnvironment["RONEOGRAPH_SETTINGS"] = settings }
        if let photos { app.launchEnvironment["RONEOGRAPH_SAMPLE_PHOTOS"] = photos.path(percentEncoded: false) }
        if let screen { app.launchEnvironment["RONEOGRAPH_SCREEN"] = screen }
        if let paperless { app.launchEnvironment["RONEOGRAPH_PAPERLESS"] = paperless }
        app.launch()
    }

    func openSettings() {
        tap(app.buttons["Settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.timeout), "Settings did not open")
    }

    /// Opens the page of an owner from Settings.
    func openOwner(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(button(name), file: file, line: line)
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: Self.timeout), "The page of \(name) did not open", file: file, line: line)
    }

    /// The first button whose label starts with `label`, as a row's label is followed by its value.
    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: Self.timeout), "\(element) does not exist", file: file, line: line)
        element.tap()
    }

    /// Taps a row of the screen titled `screen`, waits for what it presents, closes it with `close`, then checks the screen is still there.
    func present(_ row: String, on screen: String = "Settings", shows presented: XCUIElement, close: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        tap(button(row), file: file, line: line)
        XCTAssertTrue(presented.waitForExistence(timeout: Self.timeout), "\(row) did not present \(presented)", file: file, line: line)
        tap(close, file: file, line: line)
        XCTAssertTrue(presented.waitForNonExistence(timeout: Self.timeout), "\(presented) did not close", file: file, line: line)
        XCTAssertTrue(app.navigationBars[screen].isHittable, "\(screen) was dismissed", file: file, line: line)
    }
}

extension XCTestCase {
    /// A folder holding one photo of a page, removed once the test is done.
    func pagePhotos() throws -> URL {
        let photos = FileManager.default.temporaryDirectory.appending(path: "RoneographUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
}
