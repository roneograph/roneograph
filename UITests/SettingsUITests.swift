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
        XCTAssertTrue(app.buttons["Me, default, Paperless not connected"].exists)
        XCTAssertTrue(roneograph.button("Add Owner…").exists)
    }

    func testAddingAnOwnerOnlyAddsARow() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        let app = roneograph.app
        let me = roneograph.button("Me, default")
        let categories = app.buttons["Categories"]
        XCTAssertTrue(categories.waitForExistence(timeout: Roneograph.timeout))
        let meFrame = me.frame

        roneograph.tap(roneograph.button("Add Owner…"))
        let name = app.alerts["New Owner"].textFields.firstMatch
        roneograph.tap(name)
        name.typeText("Fernwood Holding")
        roneograph.tap(app.alerts["New Owner"].buttons["Add"])

        XCTAssertTrue(app.buttons["Fernwood Holding, Paperless not connected"].waitForExistence(timeout: Roneograph.timeout))
        XCTAssertEqual(me.frame, meFrame, "The first owner moved")
        XCTAssertTrue(categories.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Me, default")).count, 1)
    }

    func testAddsAnAddressOnTheOwnerPage() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        roneograph.openOwner("Me")
        let app = roneograph.app
        XCTAssertTrue(app.staticTexts["Type your name above: documents addressed to you are then recognized."].exists)
        roneograph.tap(roneograph.button("Add Address…"))
        let sheet = app.navigationBars["New Address"]
        XCTAssertTrue(sheet.waitForExistence(timeout: Roneograph.timeout), "New Address did not open")
        app.typeText("8 rue des Glycines 69007 Lyon")
        roneograph.tap(sheet.buttons["Done"])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: Roneograph.timeout))
        XCTAssertTrue(app.buttons["8 rue des Glycines 69007 Lyon"].waitForExistence(timeout: Roneograph.timeout), "The address is not listed")
        XCTAssertTrue(app.navigationBars["Me"].isHittable)
    }

    func testConnectKeepsTheOwnerPage() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        roneograph.openOwner("Me")
        let paperless = roneograph.app.navigationBars["Paperless for Me"]
        roneograph.present("Archive to Paperless", on: "Me", shows: paperless, close: paperless.buttons["Cancel"])
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
        roneograph.openOwner("Me")
        roneograph.tap(roneograph.button("Archive to Paperless"))
        roneograph.tap(roneograph.button("What Archive Sends"))
        XCTAssertTrue(roneograph.app.staticTexts["{{ correspondent }}"].waitForExistence(timeout: Roneograph.timeout), "What Archive Sends did not open")
    }

    func testPaperlessSetupShowsUnreachableServer() {
        let roneograph = Roneograph()
        roneograph.openSettings()
        roneograph.openOwner("Me")
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
