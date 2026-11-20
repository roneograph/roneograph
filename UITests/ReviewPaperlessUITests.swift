import XCTest

@MainActor
final class ReviewPaperlessUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The default owner, connected to a server listing these correspondents and document types.
    private func launch() throws -> Roneograph {
        let id = UUID().uuidString
        let settings = #"{"owners": [{"id": "\#(id)", "name": "Me", "paperless": {"url": "https://paperless.example.com/"}}], "defaultOwnerID": "\#(id)"}"#
        let paperless = #"{"correspondents": ["Lumen Energy SAS", "Northwind Traders"], "document_types": ["Invoice", "Tax"]}"#
        let roneograph = Roneograph(settings: settings, photos: try pagePhotos(), paperless: paperless)
        XCTAssertTrue(roneograph.app.buttons["Archive"].waitForExistence(timeout: Roneograph.timeout), "Review did not open with Archive")
        return roneograph
    }

    private func editIssuer(in roneograph: Roneograph, typing text: String) -> XCUIElement {
        let app = roneograph.app
        roneograph.tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Issuer' OR label == 'Add Issuer'")).firstMatch)
        let sheet = app.navigationBars["Issuer"]
        XCTAssertTrue(sheet.waitForExistence(timeout: Roneograph.timeout), "The Issuer sheet did not open")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Roneograph.timeout), "The keyboard is not up")
        app.textFields.firstMatch.clearText()
        app.typeText(text)
        return sheet
    }

    func testOffersTheCorrespondentsOfTheServerForTheIssuer() throws {
        let roneograph = try launch()
        let app = roneograph.app
        let sheet = editIssuer(in: roneograph, typing: "northwind")
        XCTAssertTrue(app.staticTexts["In Paperless as Northwind Traders."].waitForExistence(timeout: Roneograph.timeout))
        roneograph.tap(app.buttons["Northwind Traders"])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: Roneograph.timeout))
        XCTAssertTrue(app.buttons["Issuer, Northwind Traders"].waitForExistence(timeout: Roneograph.timeout), "The correspondent picked is not the issuer")
    }

    func testMarksAnIssuerArchivingAddsToPaperless() throws {
        let roneograph = try launch()
        let app = roneograph.app
        let sheet = editIssuer(in: roneograph, typing: "Fernwood Bakery")
        XCTAssertTrue(app.staticTexts["New in Paperless: archiving adds this correspondent."].waitForExistence(timeout: Roneograph.timeout))
        roneograph.tap(sheet.buttons["Done"])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: Roneograph.timeout))
        XCTAssertTrue(app.buttons["Issuer, Fernwood Bakery, new in Paperless"].waitForExistence(timeout: Roneograph.timeout), "The new issuer is not marked")
    }

    func testOffersTheDocumentTypesOfTheServer() throws {
        let roneograph = try launch()
        let app = roneograph.app
        roneograph.tap(roneograph.button("Type, "))
        roneograph.tap(app.buttons["Tax"])
        XCTAssertTrue(app.buttons["Type, Tax"].waitForExistence(timeout: Roneograph.timeout), "The document type of the server was not picked")
    }
}

extension XCUIElement {
    /// Deletes the text of a field that has the focus.
    func clearText() {
        guard let text = value as? String, !text.isEmpty, text != placeholderValue else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }
}
