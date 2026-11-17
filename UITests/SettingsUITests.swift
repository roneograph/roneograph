import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    private static let connectedSettings = """
        {"owners": [{"id": "6F1C2D3E-0000-4000-8000-000000000001", "name": "Personal", "paperless": {"url": "https://127.0.0.1:9/", "storagePath": {"id": 1, "name": "Inbox"}}}]}
        """

    override func setUp() {
        continueAfterFailure = false
    }

    func testShowsTheOwnersWithASingleOwner() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        let app = roneograph.app
        XCTAssertTrue(app.staticTexts["OWNERS"].exists || app.staticTexts["Owners"].exists, "No Owners section")
        XCTAssertTrue(app.buttons["Personal, default, sends by Share"].exists, "Save to Files needs a folder to send in one tap")
        XCTAssertTrue(roneograph.button("Add Owner…").exists)
    }

    func testAddingAnOwnerOnlyAddsARow() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        let app = roneograph.app
        let personal = roneograph.button("Personal")
        let askForName = app.switches["Ask for a name"]
        XCTAssertTrue(askForName.waitForExistence(timeout: Roneograph.timeout))
        let personalFrame = personal.frame

        roneograph.tap(roneograph.button("Add Owner…"))
        let name = app.alerts["New Owner"].textFields.firstMatch
        roneograph.tap(name)
        name.typeText("Fernwood Holding")
        roneograph.tap(app.alerts["New Owner"].buttons["Add"])

        XCTAssertTrue(app.buttons["Fernwood Holding, sends by Share"].waitForExistence(timeout: Roneograph.timeout))
        XCTAssertEqual(personal.frame, personalFrame, "The first owner moved")
        XCTAssertTrue(askForName.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Personal, default")).count, 1)
    }

    func testConnectKeepsTheOwnerPage() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        roneograph.openOwner("Personal")
        let paperless = roneograph.app.navigationBars["Paperless for Personal"]
        roneograph.present("Archive to Paperless", on: "Personal", shows: paperless, close: paperless.buttons["Cancel"])
    }

    func testServerRowKeepsTheOwnerPageAndDisconnects() {
        let roneograph = Roneograph(settings: Self.connectedSettings)
        roneograph.openSettings()
        roneograph.openOwner("Personal")
        let app = roneograph.app
        let paperless = app.navigationBars["Paperless for Personal"]
        roneograph.present("Archive to Paperless", on: "Personal", shows: paperless, close: paperless.buttons["Cancel"])
        XCTAssertTrue(app.staticTexts["127.0.0.1 · Inbox"].exists)

        roneograph.tap(roneograph.button("Archive to Paperless"))
        roneograph.tap(app.buttons["Disconnect"])
        XCTAssertTrue(paperless.waitForNonExistence(timeout: Roneograph.timeout))
        XCTAssertTrue(app.staticTexts["Connect…"].waitForExistence(timeout: Roneograph.timeout))
        XCTAssertTrue(app.navigationBars["Personal"].isHittable)
    }

    func testPaperlessSetupShowsWhatArchiveSends() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        roneograph.openOwner("Personal")
        roneograph.tap(roneograph.button("Archive to Paperless"))
        roneograph.tap(roneograph.button("What Archive Sends"))
        XCTAssertTrue(roneograph.app.staticTexts["{{ correspondent }}"].waitForExistence(timeout: Roneograph.timeout), "What Archive Sends did not open")
    }

    func testFolderPickerKeepsTheOwnerPage() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        roneograph.openOwner("Personal")
        let cancel = roneograph.app.buttons["Cancel"]
        roneograph.present("Folder", on: "Personal", shows: cancel, close: cancel)
    }

    func testPaperlessSetupShowsUnreachableServer() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        roneograph.openOwner("Personal")
        roneograph.tap(roneograph.button("Archive to Paperless"))
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
