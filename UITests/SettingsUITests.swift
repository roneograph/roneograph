import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    private static let connectedSettings = """
        {"owners": [{"id": "6F1C2D3E-0000-4000-8000-000000000001", "name": "Personal", "paperless": {"url": "https://127.0.0.1:9/", "storagePath": {"id": 1, "name": "Inbox"}}}]}
        """

    override func setUp() {
        continueAfterFailure = false
    }

    func testConnectKeepsSettings() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        let paperless = roneograph.app.navigationBars["Paperless"]
        roneograph.present("Connect…", shows: paperless, close: paperless.buttons["Cancel"])
    }

    func testServerRowsKeepSettings() {
        let roneograph = Roneograph(settings: Self.connectedSettings)
        roneograph.openSettings()
        let paperless = roneograph.app.navigationBars["Paperless"]
        roneograph.present("Server", shows: paperless, close: paperless.buttons["Cancel"])
        roneograph.present("Storage path", shows: paperless, close: paperless.buttons["Cancel"])
    }

    func testPaperlessSetupShowsWhatArchiveSends() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        roneograph.tap(roneograph.button("Connect…"))
        roneograph.tap(roneograph.button("What Archive Sends"))
        XCTAssertTrue(roneograph.app.staticTexts["{{ correspondent }}"].waitForExistence(timeout: Roneograph.timeout), "What Archive Sends did not open")
    }

    func testFolderPickerKeepsSettings() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        let cancel = roneograph.app.buttons["Cancel"]
        roneograph.present("Folder", shows: cancel, close: cancel)
    }

    func testPaperlessSetupShowsUnreachableServer() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        roneograph.tap(roneograph.button("Connect…"))
        let app = roneograph.app
        let address = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "https://paperless.example.com")).firstMatch
        roneograph.tap(address)
        address.typeText("https://127.0.0.1:9")
        let token = app.secureTextFields.firstMatch
        roneograph.tap(token)
        token.typeText("not-a-token")
        roneograph.tap(app.buttons["Connect"])
        XCTAssertTrue(app.staticTexts["The server cannot be reached."].waitForExistence(timeout: Roneograph.timeout))
    }
}
