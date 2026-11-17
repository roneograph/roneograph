import XCTest

/// The app, launched with fresh settings and no scans, and the steps the tests share.
@MainActor
struct Roneograph {
    let app = XCUIApplication()
    static let timeout: TimeInterval = 10

    /// `settings` is the JSON of the settings to start from; the keys left out take their defaults.
    init(settings: String? = nil) {
        app.launchEnvironment["RONEOGRAPH_UI_TESTING"] = "1"
        if let settings { app.launchEnvironment["RONEOGRAPH_SETTINGS"] = settings }
        app.launch()
    }

    func openSettings() {
        tap(app.buttons["Settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.timeout), "Settings did not open")
    }

    /// The first button whose label starts with `label`, as a row's label is followed by its value.
    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: Self.timeout), "\(element) does not exist", file: file, line: line)
        element.tap()
    }

    /// Taps a row of Settings, waits for what it presents, closes it with `close`, then checks Settings is still there.
    func present(_ row: String, shows presented: XCUIElement, close: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        tap(button(row), file: file, line: line)
        XCTAssertTrue(presented.waitForExistence(timeout: Self.timeout), "\(row) did not present \(presented)", file: file, line: line)
        tap(close, file: file, line: line)
        XCTAssertTrue(presented.waitForNonExistence(timeout: Self.timeout), "\(presented) did not close", file: file, line: line)
        XCTAssertTrue(app.navigationBars["Settings"].isHittable, "Settings was dismissed", file: file, line: line)
    }
}
