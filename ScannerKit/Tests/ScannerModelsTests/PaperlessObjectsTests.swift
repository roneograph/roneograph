import Foundation
import ScannerKit
import ScannerKitTesting
@testable import ScannerModels
import Testing

/// The correspondents and document types of the owners' Paperless servers: read ahead, offered in Review, and the names the details take.
@MainActor
@Suite(.serialized)
struct PaperlessObjectsTests {
    let fixture: Fixture
    let uploader = FakeUploader()
    let tokens = MemoryTokens()
    let server = FakeServer()
    let app: AppModel
    var catalogFile: URL { fixture.root.appending(path: "Paperless.json") }

    init() throws {
        fixture = try Fixture()
        app = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: Archiver(uploader: uploader, tokens: tokens, directory: fixture.root.appending(path: "Uploads"), catalogFile: fixture.root.appending(path: "Paperless.json"), fetch: server.fetch))
    }

    private func connect(_ ownerID: UUID? = nil) throws {
        var owner = fixture.settings.value.owner(ownerID)
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        fixture.settings.value.updateOwner(owner)
        try tokens.setToken("secret", for: owner.id)
    }

    private func answer(correspondents: [String], documentTypes: [String] = []) {
        func page(_ names: [String]) -> String {
            let results = names.enumerated().map { #"{"id": \#($0.offset + 1), "name": "\#($0.element)"}"# }.joined(separator: ", ")
            return #"{"next": null, "results": [\#(results)]}"#
        }
        server.answer("GET", "/api/correspondents/", page(correspondents))
        server.answer("GET", "/api/document_types/", page(documentTypes))
    }

    /// A scan whose first page reads as these lines from the top.
    private func scan(reading texts: [String]) async -> ScanModel {
        let model = app.startScan()
        let lines = texts.enumerated().map { TextLine(text: $1, frame: CGRect(x: 0.08, y: 0.04 + Double($0) * 0.03, width: 0.4, height: 0.012)) }
        model.readDocument = { _, _, owners in DocumentDetector().detect(lines: lines, owners: owners) }
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await model.waitUntilIdle()
        app.finishCapture(model)
        return model
    }

    @Test func readsTheObjectsOfTheConnectedOwnersOnly() async throws {
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        try connect()
        answer(correspondents: ["Lumen"], documentTypes: ["Invoice"])

        await app.readPaperless()
        #expect(server.requests.map { $0.url?.path() } == ["/api/correspondents/", "/api/document_types/"])
        #expect(app.paperlessObjects(.correspondent, of: fixture.settings.value.defaultOwner)?.objects.map(\.name) == ["Lumen"])
        #expect(app.paperlessObjects(.documentType, of: fixture.settings.value.owner(holding.id)) == nil)
    }

    @Test func readsAgainOnlyWhatIsOlderThanAsked() async throws {
        try connect()
        answer(correspondents: ["Lumen"])
        await app.readPaperless(unlessReadWithin: AppModel.paperlessObjectsLifetime)
        await app.readPaperless(unlessReadWithin: AppModel.paperlessObjectsLifetime)
        #expect(server.requests.count == 2)

        answer(correspondents: ["Lumen", "Voltaria"])
        await app.readPaperless()
        #expect(server.requests.count == 4)
        #expect(app.paperlessObjects(.correspondent, of: fixture.settings.value.defaultOwner)?.objects.count == 2)
    }

    @Test func namesTheScansNotSentLikeTheServerOnceRead() async throws {
        try connect()
        let scan = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])
        #expect(scan.scan.details.issuer == "Lumen Energy")
        let sent = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])
        sent.markSent(.share)

        answer(correspondents: ["Lumen", "Voltaria"], documentTypes: ["invoice"])
        await app.readPaperless()
        #expect(scan.scan.details.issuer == "Lumen")
        #expect(scan.scan.details.documentType == DocumentType("invoice"))
        #expect(scan.scan.suggestions.first?.contains("Lumen Energy") == false)
        #expect(sent.scan.details.issuer == "Lumen Energy")
    }

    @Test func readsTheIssuerAsTheCorrespondentItStandsFor() async throws {
        try connect()
        answer(correspondents: ["Lumen", "Voltaria"], documentTypes: ["Invoice", "Tax"])
        await app.readPaperless()

        let scan = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])
        #expect(scan.scan.details.issuer == "Lumen")
        #expect(scan.scan.details.documentType == .invoice)
        #expect(scan.newInPaperless.isEmpty)
    }

    @Test func aCorrectedIssuerIsRememberedAsTheCorrespondentItStandsFor() async throws {
        try connect()
        answer(correspondents: ["Lumen Power", "Voltaria"], documentTypes: ["Tax"])
        await app.readPaperless()
        let first = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])

        first.setDetail(\.issuer, to: "LUMEN POWER SAS")
        first.setDetails(DocumentDetails(documentType: .taxNotice, issuer: first.scan.details.issuer))
        #expect(first.scan.details.issuer == "Lumen Power")
        #expect(first.scan.details.documentType == DocumentType("Tax"))
        let learned = try #require(fixture.settings.learnedIssuer(for: first.scan.issuerKeys))
        #expect(learned.issuer == "Lumen Power")
        #expect(learned.documentType == DocumentType("Tax"))

        let second = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])
        #expect(second.scan.details.issuer == "Lumen Power")
        #expect(second.scan.remembered.contains(.issuer))
    }

    @Test func anIssuerRememberedBeforeConnectingTakesTheNameOfItsCorrespondent() async throws {
        let first = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])
        first.setDetail(\.issuer, to: "Lumen Power")
        try connect()
        answer(correspondents: ["Lumen Power SAS"])
        await app.readPaperless()

        let second = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])
        #expect(second.scan.details.issuer == "Lumen Power SAS")
        #expect(second.scan.remembered.contains(.issuer))
    }

    @Test func tellsWhatArchivingAddsToTheServer() async throws {
        let scan = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])
        scan.setDetails(DocumentDetails(documentType: .payslip, issuer: "Northwind"))
        #expect(scan.newInPaperless.isEmpty, "Nothing is known without a server")

        try connect()
        answer(correspondents: ["Lumen"], documentTypes: ["Invoice"])
        await app.readPaperless()
        #expect(scan.newInPaperless == [.correspondent, .documentType])

        scan.setDetails(DocumentDetails(documentType: .other, issuer: "Lumen"))
        #expect(scan.newInPaperless.isEmpty)
    }

    @Test func saysWhetherTheTypedIssuerIsInPaperless() async throws {
        let scan = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])
        let unknown = "Read on the page. A new issuer is reused for the next documents from the same issuer, along with the document type."
        #expect(scan.issuerFooter(for: "Northwind") == unknown)
        #expect(scan.newDocumentTypeMessage == nil)

        try connect()
        answer(correspondents: ["Lumen", "Northwind Traders"], documentTypes: ["Invoice"])
        await app.readPaperless()
        #expect(scan.issuerFooter(for: "Lumen") == "In Paperless.")
        #expect(scan.issuerFooter(for: "northwind") == "In Paperless as Northwind Traders.")
        #expect(scan.issuerFooter(for: "Fernwood") == "New in Paperless: archiving adds this correspondent.")
        #expect(scan.issuerFooter(for: " ") == unknown)
        #expect(scan.newDocumentTypeMessage == "Archiving adds it to Paperless.")
    }

    @Test func offersTheDocumentTypesOfTheServerWithTheCurrentOneAndOther() async throws {
        let scan = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])
        scan.setDetails(DocumentDetails(documentType: .medical))
        #expect(scan.documentTypes == fixture.settings.value.allDocumentTypes)

        try connect()
        answer(correspondents: [], documentTypes: ["Tax", "Bank statement", "Invoice"])
        await app.readPaperless()
        #expect(scan.documentTypes == [.bankStatement, .invoice, .medical, DocumentType("Tax"), .other])
    }

    @Test func aNewDocumentTypeForAConnectedOwnerIsLeftToTheServer() async throws {
        try connect()
        answer(correspondents: [], documentTypes: ["Invoice"])
        await app.readPaperless()
        let scan = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])

        scan.addDocumentType(" warranty  card ")
        #expect(scan.scan.details.documentType == DocumentType("warranty card"))
        #expect(fixture.settings.value.documentTypes.isEmpty)
        #expect(scan.newInPaperless.contains(.documentType))
    }

    @Test func aNewDocumentTypeWithoutServerJoinsTheUsersOnes() async throws {
        let scan = await self.scan(reading: ["LUMEN ENERGY SAS", "Invoice"])
        scan.addDocumentType("Warranty")
        #expect(scan.scan.details.documentType == DocumentType("Warranty"))
        #expect(fixture.settings.value.documentTypes == [DocumentType("Warranty")])
    }

    @Test func keepsWhatWasReadForTheNextLaunchWhileTheServerCannotBeReached() async throws {
        try connect()
        answer(correspondents: ["Lumen"])
        await app.readPaperless()

        let offline = FakeServer()
        offline.answer("GET", "/api/correspondents/", "", status: 503)
        let later = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: Archiver(uploader: FakeUploader(), tokens: tokens, directory: fixture.root.appending(path: "Uploads"), catalogFile: catalogFile, fetch: offline.fetch))
        await later.readPaperless()
        #expect(later.paperlessObjects(.correspondent, of: fixture.settings.value.defaultOwner)?.objects.map(\.name) == ["Lumen"])
    }

    @Test func forgetsWhatWasReadOnceDisconnected() async throws {
        try connect()
        answer(correspondents: ["Lumen"])
        await app.readPaperless()

        PaperlessSetup.disconnect(fixture.settings.value.defaultOwnerID, settings: fixture.settings, archiver: try #require(app.archiver))
        try connect()
        #expect(app.paperlessObjects(.correspondent, of: fixture.settings.value.defaultOwner) == nil)
        #expect(!FileManager.default.contents(atPath: catalogFile.path(percentEncoded: false)).map { String(decoding: $0, as: UTF8.self).contains("Lumen") }!)
    }

    @Test func readsTheObjectsOfAnOwnerOnceConnected() async throws {
        answer(correspondents: ["Lumen"])
        try connect()
        try app.archiver?.setToken("secret", for: fixture.settings.value.defaultOwnerID)
        await app.readingPaperless?.value
        #expect(app.paperlessObjects(.correspondent, of: fixture.settings.value.defaultOwner)?.objects.map(\.name) == ["Lumen"])
    }

    @Test func anUploadReadsTheObjectsAgainAfterALaunch() async throws {
        try connect()
        answer(correspondents: ["Lumen"])
        await app.readPaperless()
        server.answer("GET", "/api/correspondents/", #"{"results": [{"id": 9, "name": "Lumen"}]}"#)
        let uploader = FakeUploader()
        let later = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: Archiver(uploader: uploader, tokens: tokens, directory: fixture.root.appending(path: "Uploads"), catalogFile: catalogFile, fetch: server.fetch))
        let scan = await fixture.capturedScan(in: later)
        scan.setDetails(DocumentDetails(issuer: "Lumen"))
        await scan.preparePDF()

        try await later.archive([scan])
        #expect(String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("name=\"correspondent\"\r\n\r\n9\r\n"))
    }
}
