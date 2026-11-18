import Foundation
import ScannerKit
import ScannerKitTesting
@testable import ScannerModels
import Synchronization
import Testing

@MainActor
@Suite(.serialized)
struct ArchiverTests {
    let fixture: Fixture
    let uploader = FakeUploader()
    let tokens = MemoryTokens()
    let server = FakeServer()
    let app: AppModel

    init() throws {
        fixture = try Fixture()
        let archiver = Archiver(uploader: uploader, tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: server.fetch)
        app = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: archiver)
    }

    private func connect(_ ownerID: UUID? = nil, storagePath: PaperlessStoragePath? = nil) throws {
        var owner = fixture.settings.value.owner(ownerID)
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!, storagePath: storagePath)
        fixture.settings.value.updateOwner(owner)
        try tokens.setToken("secret", for: owner.id)
    }

    private func readyScan() async -> ScanModel {
        let scan = await fixture.capturedScan(in: app)
        scan.rename("Lumen invoice")
        await scan.preparePDF()
        return scan
    }

    @Test func forgetsTheTokensNoOwnerWithAServerUsesOnLaunch() throws {
        try connect()
        let leftOver = UUID()
        try tokens.setToken("old", for: leftOver)
        let disconnected = try #require(fixture.settings.addOwner("Holding"))
        try tokens.setToken("stale", for: disconnected.id)
        let archiver = Archiver(uploader: uploader, tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: server.fetch)

        _ = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: archiver)

        #expect(tokens.ownerIDs() == [fixture.settings.value.defaultOwnerID])
    }

    @Test func keepsTheTokensWhileSettingsItCouldNotReadAreSetAside() throws {
        let ownerID = UUID()
        try tokens.setToken("secret", for: ownerID)
        fixture.defaults.set(Data(#"{"autoCapture":"sometimes"}"#.utf8), forKey: "settings")
        let settings = SettingsStore(defaults: fixture.defaults)
        let archiver = Archiver(uploader: uploader, tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: server.fetch)

        _ = AppModel(processor: fixture.processor, settings: settings, archiver: archiver)
        settings.value.autoCapture = false
        settings.save()
        _ = AppModel(processor: fixture.processor, settings: SettingsStore(defaults: fixture.defaults), archiver: archiver)

        #expect(tokens.token(for: ownerID) == "secret")
    }

    @Test func showsArchiveOnlyWhenTheOwnerOfTheScanIsConnected() async throws {
        let holding = try #require(fixture.settings.addOwner("Holding"))
        let personal = await readyScan()
        let company = await readyScan()
        company.setOwner(holding.id)
        #expect(!app.archives(personal))
        #expect(app.ownerToConnect(for: personal)?.id == fixture.settings.value.defaultOwnerID)

        try connect()
        #expect(app.archives(personal))
        #expect(app.ownerToConnect(for: personal) == nil)
        #expect(!app.archives(company))
        #expect(app.ownerToConnect(for: company)?.id == holding.id)

        try connect(holding.id)
        #expect(app.archives(company))
    }

    @Test func hidesArchiveWhenTheTokenIsMissing() async throws {
        let scan = await readyScan()
        var owner = scan.owner
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        fixture.settings.value.updateOwner(owner)
        #expect(!app.archives(scan))
        #expect(app.ownerToConnect(for: scan)?.id == owner.id)
    }

    @Test func uploadsThePDFWithItsTitleAndStoragePath() async throws {
        try connect(storagePath: PaperlessStoragePath(id: 7, name: "Personal"))
        let scan = await readyScan()
        guard case .ready(let url, _) = scan.pdf else { Issue.record("No PDF"); return }

        try await app.archive([scan])
        let upload = try #require(uploader.uploads.first)
        #expect(upload.scanID == scan.id)
        #expect(upload.delay == .zero)
        #expect(upload.request.url?.absoluteString == "https://paperless.example.com/api/documents/post_document/")
        #expect(upload.request.value(forHTTPHeaderField: "Authorization") == "Token secret")
        let body = String(decoding: upload.body, as: UTF8.self)
        #expect(body.contains("name=\"title\"\r\n\r\nLumen invoice\r\n"))
        #expect(body.contains("name=\"storage_path\"\r\n\r\n7\r\n"))
        #expect(body.contains("filename=\"\(url.lastPathComponent)\""))
        #expect(upload.body.range(of: try Data(contentsOf: url)) != nil)
        #expect(scan.scan.archiving == Archiving())
        #expect(scan.scan.sent == nil)
        #expect(app.toast == "Archiving to Paperless")
        #expect(app.notSent.isEmpty)
    }

    @Test func sendsTheDocumentTypeNamedLikeTheCategory() async throws {
        try connect()
        server.answer("GET", "/api/document_types/", #"{"results": [{"id": 3, "name": "invoice"}]}"#)
        let first = await readyScan()
        first.setDetails(DocumentDetails(category: .invoice))
        let second = await readyScan()
        second.setDetails(DocumentDetails(category: .invoice))
        await first.preparePDF()
        await second.preparePDF()

        try await app.archive([first, second])
        #expect(uploader.uploads.count == 2)
        #expect(uploader.uploads.allSatisfy { String(decoding: $0.body, as: UTF8.self).contains("name=\"document_type\"\r\n\r\n3\r\n") })
        #expect(server.requests(to: "/api/document_types/").map(\.httpMethod) == ["GET"], "The types are read once")
    }

    @Test func readsTheTypesWithTheTokenOfEachOwnerOfTheSameServer() async throws {
        let holding = try #require(fixture.settings.addOwner("Holding"))
        try connect()
        try connect(holding.id)
        try tokens.setToken("mine", for: fixture.settings.value.defaultOwnerID)
        try tokens.setToken("theirs", for: holding.id)
        server.answer("GET", "/api/document_types/", #"{"results": [{"id": 3, "name": "Invoice"}]}"#)
        server.answer("GET", "/api/document_types/", #"{"results": [{"id": 7, "name": "Invoice"}]}"#)
        let mine = await readyScan()
        mine.setDetails(DocumentDetails(category: .invoice))
        let theirs = await readyScan()
        theirs.setDetails(DocumentDetails(category: .invoice))
        theirs.setOwner(holding.id)
        await mine.preparePDF()
        await theirs.preparePDF()

        try await app.archive([mine, theirs])
        #expect(server.requests(to: "/api/document_types/").map { $0.value(forHTTPHeaderField: "Authorization") } == ["Token mine", "Token theirs"])
        #expect(String(decoding: try #require(uploader.uploads.last).body, as: UTF8.self).contains("name=\"document_type\"\r\n\r\n7\r\n"))
    }

    @Test func createsTheDocumentTypeOfANewCategory() async throws {
        try connect()
        server.answer("GET", "/api/document_types/", #"{"results": []}"#)
        server.answer("POST", "/api/document_types/", #"{"id": 8, "name": "Payslip"}"#, status: 201)
        let scan = await readyScan()
        scan.setDetails(DocumentDetails(category: .payslip))
        await scan.preparePDF()

        try await app.archive([scan])
        let created = try #require(server.requests(to: "/api/document_types/").last)
        #expect(String(decoding: created.httpBody ?? Data(), as: UTF8.self) == #"{"matching_algorithm":0,"name":"Payslip"}"#)
        #expect(String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("name=\"document_type\"\r\n\r\n8\r\n"))
    }

    @Test func createsAMissingTypeWithoutReadingTheTypesAgain() async throws {
        try connect()
        server.answer("GET", "/api/document_types/", #"{"results": [{"id": 3, "name": "Invoice"}]}"#)
        server.answer("POST", "/api/document_types/", #"{"id": 8, "name": "Payslip"}"#, status: 201)
        let invoice = await readyScan()
        invoice.setDetails(DocumentDetails(category: .invoice))
        let payslip = await readyScan()
        payslip.setDetails(DocumentDetails(category: .payslip))
        await invoice.preparePDF()
        await payslip.preparePDF()

        try await app.archive([invoice, payslip])
        #expect(server.requests(to: "/api/document_types/").map(\.httpMethod) == ["GET", "POST"])
        #expect(String(decoding: try #require(uploader.uploads.last).body, as: UTF8.self).contains("name=\"document_type\"\r\n\r\n8\r\n"))
    }

    @Test func sendsOtherDocumentsWithoutAType() async throws {
        try connect()
        let scan = await readyScan()

        try await app.archive([scan])
        #expect(server.requests(to: "/api/document_types/").isEmpty)
        #expect(!String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("document_type"))
    }

    @Test func sendsWithoutATypeWhenTheServerRefusesToCreateIt() async throws {
        try connect()
        server.answer("GET", "/api/document_types/", #"{"results": []}"#)
        server.answer("POST", "/api/document_types/", #"{"detail": "You do not have permission to perform this action."}"#, status: 403)
        let scan = await readyScan()
        scan.setDetails(DocumentDetails(category: .receipt))
        await scan.preparePDF()

        try await app.archive([scan])
        #expect(!String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("document_type"))
    }

    @Test func waitsForTheAppToBeActiveAgainWhenTheServerCannotBeReachedForTheType() async throws {
        try connect()
        server.answer("GET", "/api/document_types/", "", status: 503)
        let scan = await readyScan()
        scan.setDetails(DocumentDetails(category: .invoice))
        await scan.preparePDF()

        try await app.archive([scan])
        #expect(uploader.uploads.isEmpty)
        #expect(scan.scan.archiving?.state == .waiting("The server is not ready (error 503)."))
        #expect(app.notSent.isEmpty)

        server.answer("GET", "/api/document_types/", #"{"results": [{"id": 3, "name": "Invoice"}]}"#)
        await app.archiver?.resume()
        #expect(uploader.uploads.count == 1)
        #expect(scan.scan.archiving == Archiving())
    }

    @Test func preparesAWaitingUploadAfterARelaunch() async throws {
        try connect()
        server.answer("GET", "/api/document_types/", "", status: 503)
        let scan = await readyScan()
        scan.setDetails(DocumentDetails(category: .invoice))
        await scan.preparePDF()
        guard case .ready(let url, _) = scan.pdf else { Issue.record("No PDF"); return }
        try await app.archive([scan])

        server.answer("GET", "/api/document_types/", #"{"results": [{"id": 3, "name": "Invoice"}]}"#)
        let (later, archiver, uploader) = relaunch()
        await archiver.resume()
        #expect(uploader.uploads.count == 1)
        #expect(later.model(for: scan.id)?.scan.archiving == Archiving())
        #expect(try #require(uploader.uploads.first).body.range(of: try Data(contentsOf: url)) != nil)
    }

    @Test func sendsTheCorrespondentNamedLikeTheIssuer() async throws {
        try connect()
        server.answer("GET", "/api/correspondents/", #"{"results": [{"id": 4, "name": "LUMEN ENERGY"}]}"#)
        let first = await readyScan()
        first.setDetails(DocumentDetails(issuer: "Lumen Energy"))
        let second = await readyScan()
        second.setDetails(DocumentDetails(issuer: " lumen energy "))
        await first.preparePDF()
        await second.preparePDF()

        try await app.archive([first, second])
        #expect(uploader.uploads.count == 2)
        #expect(uploader.uploads.allSatisfy { String(decoding: $0.body, as: UTF8.self).contains("name=\"correspondent\"\r\n\r\n4\r\n") })
        #expect(server.requests(to: "/api/correspondents/").map(\.httpMethod) == ["GET"], "The correspondents are read once")
    }

    @Test func createsTheCorrespondentOfANewIssuer() async throws {
        try connect()
        server.answer("GET", "/api/correspondents/", #"{"results": []}"#)
        server.answer("POST", "/api/correspondents/", #"{"id": 11, "name": "Lumen Energy"}"#, status: 201)
        let scan = await readyScan()
        scan.setDetails(DocumentDetails(issuer: "Lumen Energy"))
        await scan.preparePDF()

        try await app.archive([scan])
        let created = try #require(server.requests(to: "/api/correspondents/").last)
        #expect(created.httpMethod == "POST")
        #expect(String(decoding: created.httpBody ?? Data(), as: UTF8.self) == #"{"matching_algorithm":0,"name":"Lumen Energy"}"#)
        #expect(String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("name=\"correspondent\"\r\n\r\n11\r\n"))
    }

    @Test(arguments: [nil, "", "  "] as [String?])
    func sendsAScanWithoutIssuerWithoutACorrespondent(issuer: String?) async throws {
        try connect()
        let scan = await readyScan()
        scan.setDetails(DocumentDetails(issuer: issuer))
        await scan.preparePDF()

        try await app.archive([scan])
        #expect(server.requests(to: "/api/correspondents/").isEmpty)
        #expect(!String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("correspondent"))
    }

    @Test func sendsWithoutACorrespondentWhenTheServerRefusesToCreateIt() async throws {
        try connect()
        server.answer("GET", "/api/correspondents/", #"{"results": []}"#)
        server.answer("POST", "/api/correspondents/", #"{"detail": "You do not have permission to perform this action."}"#, status: 403)
        let scan = await readyScan()
        scan.setDetails(DocumentDetails(issuer: "Lumen Energy"))
        await scan.preparePDF()

        try await app.archive([scan])
        #expect(!String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("correspondent"))
    }

    @Test func waitsForTheAppToBeActiveAgainWhenTheServerCannotBeReachedForTheCorrespondent() async throws {
        try connect()
        server.answer("GET", "/api/correspondents/", "", status: 503)
        let scan = await readyScan()
        scan.setDetails(DocumentDetails(issuer: "Lumen Energy"))
        await scan.preparePDF()

        try await app.archive([scan])
        #expect(uploader.uploads.isEmpty)
        #expect(scan.scan.archiving?.state == .waiting("The server is not ready (error 503)."))
        #expect(app.scans.first?.status == "Waiting for Paperless · 1 page")

        server.answer("GET", "/api/correspondents/", #"{"results": [{"id": 4, "name": "Lumen Energy"}]}"#)
        await app.archiver?.resume()
        #expect(String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("name=\"correspondent\"\r\n\r\n4\r\n"))
    }

    @Test func sendsTheOwnerInTheOwnerCustomField() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", #"{"results": [{"id": 5, "name": "Owner", "data_type": "string"}]}"#, version: "2.19.0")
        let first = await readyScan()
        let second = await readyScan()

        try await app.archive([first, second])
        #expect(uploader.uploads.count == 2)
        #expect(uploader.uploads.allSatisfy { String(decoding: $0.body, as: UTF8.self).contains("name=\"custom_fields\"\r\n\r\n{\"5\":\"Me\"}\r\n") })
        #expect(server.requests(to: "/api/custom_fields/").map(\.httpMethod) == ["GET"], "The fields are read once")
    }

    @Test func createsTheOwnerCustomFieldWhenMissing() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", #"{"results": [{"id": 4, "name": "owner", "data_type": "string"}]}"#, version: "3.5.0")
        server.answer("POST", "/api/custom_fields/", #"{"id": 6, "name": "Owner", "data_type": "string"}"#, status: 201)
        let scan = await readyScan()

        try await app.archive([scan])
        let created = try #require(server.requests(to: "/api/custom_fields/").last)
        #expect(created.httpMethod == "POST")
        #expect(String(decoding: created.httpBody ?? Data(), as: UTF8.self) == #"{"data_type":"string","name":"Owner"}"#)
        #expect(String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("name=\"custom_fields\"\r\n\r\n{\"6\":\"Me\"}\r\n"))
    }

    @Test func sendsWithoutTheOwnerToAServerTooOldToTakeIt() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", #"{"results": [{"id": 5, "name": "Owner", "data_type": "string"}]}"#, version: "2.18.4")
        let first = await readyScan()
        let second = await readyScan()

        try await app.archive([first, second])
        #expect(uploader.uploads.count == 2)
        #expect(uploader.uploads.allSatisfy { !String(decoding: $0.body, as: UTF8.self).contains("custom_fields") })
        #expect(server.requests(to: "/api/custom_fields/").map(\.httpMethod) == ["GET"])
    }

    @Test func sendsWithoutTheOwnerWhenItsFieldDoesNotTakeText() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", #"{"results": [{"id": 5, "name": "Owner", "data_type": "select"}]}"#, version: "2.19.0")
        let scan = await readyScan()

        try await app.archive([scan])
        #expect(!String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("custom_fields"))
        #expect(server.requests(to: "/api/custom_fields/").map(\.httpMethod) == ["GET"])
    }

    @Test func sendsWithoutTheOwnerWhenTheServerRefusesToCreateItsField() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", #"{"results": []}"#, version: "2.19.0")
        server.answer("POST", "/api/custom_fields/", #"{"detail": "You do not have permission to perform this action."}"#, status: 403)
        let scan = await readyScan()

        try await app.archive([scan])
        #expect(!String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("custom_fields"))
    }

    @Test func sendsTheCommentInALongTextCommentField() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", #"{"results": [{"id": 5, "name": "Owner", "data_type": "string"}]}"#, version: "2.19.0")
        server.answer("POST", "/api/custom_fields/", #"{"id": 6, "name": "Comment", "data_type": "longtext"}"#, status: 201)
        let comment = "Lunch with Ada and Linus to plan the release of the next version, with the whole team, at the café next to the office, which took longer than planned"
        let scan = await readyScan()
        scan.setComment(comment)
        await scan.preparePDF()

        try await app.archive([scan])
        let created = try #require(server.requests(to: "/api/custom_fields/").last)
        #expect(String(decoding: created.httpBody ?? Data(), as: UTF8.self) == #"{"data_type":"longtext","name":"Comment"}"#)
        #expect(String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("name=\"custom_fields\"\r\n\r\n{\"5\":\"Me\",\"6\":\"\(comment)\"}\r\n"))
    }

    @Test func cutsTheCommentInACommentFieldOfShortText() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", #"{"results": [{"id": 7, "name": "Comment", "data_type": "string"}]}"#, version: "2.19.0")
        let scan = await readyScan()
        scan.setComment(String(repeating: "a", count: 200))
        await scan.preparePDF()

        try await app.archive([scan])
        #expect(String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("\"7\":\"\(String(repeating: "a", count: 128))\"}"))
    }

    @Test func createsNoCommentFieldForAScanWithoutComment() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", #"{"results": [{"id": 5, "name": "Owner", "data_type": "string"}]}"#, version: "2.19.0")
        let scan = await readyScan()

        try await app.archive([scan])
        #expect(server.requests(to: "/api/custom_fields/").map(\.httpMethod) == ["GET"])
        #expect(String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("{\"5\":\"Me\"}"))
    }

    @Test func sendsWithoutTheCommentToAServerTooOldToTakeIt() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", #"{"results": []}"#, version: "2.18.4")
        let scan = await readyScan()
        scan.setComment("Lunch with Ada")
        await scan.preparePDF()

        try await app.archive([scan])
        #expect(!String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("custom_fields"))
        #expect(server.requests(to: "/api/custom_fields/").map(\.httpMethod) == ["GET"])
    }

    @Test func waitsForTheAppToBeActiveAgainWhenTheServerCannotBeReachedForTheOwnerField() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", "", status: 502)
        let scan = await readyScan()

        try await app.archive([scan])
        #expect(uploader.uploads.isEmpty)
        #expect(scan.scan.archiving?.state == .waiting("The server is not ready (error 502)."))

        server.answer("GET", "/api/custom_fields/", #"{"results": [{"id": 5, "name": "Owner", "data_type": "string"}]}"#, version: "2.19.0")
        await app.archiver?.resume()
        #expect(String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("{\"5\":\"Me\"}"))
    }

    @Test func readsTheOwnerFieldAgainAfterAFailedUpload() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", #"{"results": [{"id": 5, "name": "Owner", "data_type": "string"}]}"#, version: "2.19.0")
        server.answer("GET", "/api/custom_fields/", #"{"results": [{"id": 9, "name": "Owner", "data_type": "string"}]}"#, version: "2.19.0")
        let scan = await readyScan()
        try await app.archive([scan])
        app.archiver?.complete(UploadResult(scanID: scan.id, status: 400, body: Data(#"{"custom_fields": ["Custom field with id 5 does not exist"]}"#.utf8)))

        try await app.archive([scan])
        #expect(String(decoding: try #require(uploader.uploads.last).body, as: UTF8.self).contains("{\"9\":\"Me\"}"))
    }

    @Test func aScanIsSentOnceTheServerTookIt() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])

        app.archiver?.complete(taken(scan))
        #expect(scan.scan.sent?.method == .paperless)
        #expect(scan.scan.archiving == nil)
        #expect(uploadFiles().isEmpty)
        #expect(app.scans.first?.status.hasPrefix("Archived") == true)
    }

    @Test func aPageThatIsNotPaperlessAnsweringTheUploadDoesNotArchiveTheScan() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])

        app.archiver?.complete(UploadResult(scanID: scan.id, status: 200, body: Data("<html><title>Sign in</title></html>".utf8)))
        #expect(scan.scan.sent == nil)
        #expect(scan.scan.archiving?.state == .failed("The server did not answer like a Paperless-ngx server."))
    }

    @Test func aRedirectedUploadDoesNotArchiveTheScan() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])

        let sent = try #require(uploader.uploads.first?.request.url)
        app.archiver?.complete(UploadResult(scanID: scan.id, status: 200, body: taskID, url: sent, responseURL: URL(string: "https://login.example.com/")))
        #expect(scan.scan.sent == nil)
        #expect(scan.scan.archiving?.state == .failed("The server redirects to another address."))
    }

    @Test func triesAgainLaterWhileTheServerIsNotReady() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])

        app.archiver?.complete(UploadResult(scanID: scan.id, status: 503))
        #expect(scan.scan.archiving == Archiving(state: .waiting("The server is not ready (error 503)."), retries: 1))
        #expect(uploader.uploads.count == 2)
        #expect(uploader.uploads[1].delay == .seconds(30))
        #expect(uploader.uploads[1].body == uploader.uploads[0].body)
        #expect(app.scans.first?.status == "Waiting for Paperless · 1 page")

        app.archiver?.complete(UploadResult(scanID: scan.id, status: nil, error: .notConnectedToInternet))
        #expect(uploader.uploads[2].delay == .seconds(60))
        app.archiver?.complete(taken(scan))
        #expect(scan.scan.sent?.method == .paperless)
    }

    @Test func givesUpAfterADayOfTries() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])

        for _ in 0...Archiver.maximumRetries {
            app.archiver?.complete(UploadResult(scanID: scan.id, status: 502))
        }
        #expect(scan.scan.archiving?.state == .failed("The server is not ready (error 502)."))
        #expect(uploader.uploads.count == Archiver.maximumRetries + 1)
        #expect(Archiver.delay(afterRetries: Archiver.maximumRetries) == .seconds(3600))
    }

    @Test func failsWithoutTryingAgainWhenTheTokenIsRefused() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])

        app.archiver?.complete(UploadResult(scanID: scan.id, status: 401))
        #expect(scan.scan.archiving?.state == .failed("The server refused the token."))
        #expect(uploader.uploads.count == 1)
        #expect(uploadFiles().isEmpty)
        #expect(app.scans.first?.status == "Not archived: The server refused the token.")
        #expect(app.notSent.map(\.id) == [scan.id])
    }

    @Test func archivingAgainAfterAFailureStartsOver() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])
        app.archiver?.complete(UploadResult(scanID: scan.id, status: 401))

        try await app.archive([scan])
        #expect(scan.scan.archiving == Archiving())
        #expect(uploader.uploads.count == 2)
    }

    @Test func refusesTheScansOfAnOwnerWithoutServer() async throws {
        let scan = await readyScan()
        await #expect(throws: Archiver.ArchiveError.notConnected(scan.owner.id)) { try await app.archive([scan]) }

        var owner = scan.owner
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        fixture.settings.value.updateOwner(owner)
        await #expect(throws: Archiver.ArchiveError.notConnected(scan.owner.id), "The token is missing") { try await app.archive([scan]) }
        #expect(uploader.uploads.isEmpty)
    }

    @Test func deletingAScanStopsItsUpload() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])

        app.delete(scan.id)
        #expect(uploader.cancelled == [scan.id])
        #expect(uploadFiles().isEmpty)
    }

    @Test func triesAgainAnUploadTheSystemCancelled() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])

        app.archiver?.complete(UploadResult(scanID: scan.id, status: nil, error: .cancelled))
        #expect(scan.scan.archiving?.retries == 1)
        #expect(uploader.uploads.count == 2)
    }

    @Test func archivingAScanWaitingForAnotherTryStartsItNow() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])
        app.archiver?.complete(UploadResult(scanID: scan.id, status: 503))

        try await app.archive([scan])
        #expect(uploader.cancelled == [scan.id])
        #expect(uploader.uploads.last?.delay == .zero)
        #expect(scan.scan.archiving == Archiving())
    }

    @Test func appliesResultsOnceTheAppIsActive() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])
        app.setActive(false)

        app.archiver?.complete(taken(scan))
        #expect(scan.scan.sent == nil)
        app.setActive(true)
        #expect(scan.scan.sent?.method == .paperless)
    }

    @Test func appliesAfterARelaunchAResultReceivedWhileTheAppWasNotActive() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])
        app.setActive(false)
        app.archiver?.complete(taken(scan))

        let (later, archiver, uploader) = relaunch()
        await activate(later, archiver)
        #expect(later.model(for: scan.id)?.scan.sent?.method == .paperless)
        #expect(later.model(for: scan.id)?.scan.archiving == nil)
        #expect(uploader.uploads.isEmpty)
        #expect(uploadFiles().isEmpty)
    }

    @Test func startsAgainAfterARelaunchAnUploadTheSessionNoLongerHas() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])
        let first = try #require(uploader.uploads.first)

        let (later, archiver, uploader) = relaunch()
        await activate(later, archiver)
        #expect(uploader.uploads.map(\.body) == [first.body])
        #expect(uploader.uploads.first?.request.value(forHTTPHeaderField: "Authorization") == "Token secret")
        #expect(later.model(for: scan.id)?.scan.archiving == Archiving())
    }

    @Test func leavesAfterARelaunchAnUploadTheSessionStillHas() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])

        let (later, archiver, _) = relaunch(uploader: uploader)
        await activate(later, archiver)
        #expect(uploader.uploads.count == 1)
        #expect(later.model(for: scan.id)?.scan.archiving == Archiving())
    }

    @Test func preparesAgainAfterARelaunchAnUploadWhosePreparationWasCutShort() async throws {
        try connect()
        let scan = await readyScan()
        let release = server.hold()
        defer { release() }
        let archiving = Task { try await app.archive([scan]) }
        try await server.waitUntilHolding(1)
        #expect(scan.scan.archiving == Archiving())

        let (later, archiver, uploader) = relaunch(server: FakeServer())
        await activate(later, archiver)
        #expect(uploader.uploads.count == 1)
        #expect(later.model(for: scan.id)?.scan.archiving == Archiving())
        archiving.cancel()
    }

    @Test func preparesAWaitingUploadOnceWhenTheAppIsActivatedTwiceInARow() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", "", status: 503)
        let scan = await readyScan()
        try await app.archive([scan])
        #expect(scan.scan.archiving?.state == .waiting("The server is not ready (error 503)."))
        let archiver = try #require(app.archiver)
        server.delay = .milliseconds(50)

        async let first: Void = archiver.resume()
        async let second: Void = archiver.resume()
        _ = await (first, second)
        #expect(uploader.uploads.count == 1)
        #expect(uploader.cancelled.isEmpty)
    }

    @Test func archivingTwiceAtOnceUploadsOnce() async throws {
        try connect()
        let scan = await readyScan()
        server.delay = .milliseconds(50)

        async let first: Void = app.archive([scan])
        async let second: Void = app.archive([scan])
        _ = try await (first, second)
        #expect(uploader.uploads.count == 1)
        #expect(scan.scan.archiving == Archiving())
    }

    @Test func failsAnUploadWhoseServerWasDisconnected() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])
        try tokens.setToken(nil, for: scan.owner.id)

        app.archiver?.complete(UploadResult(scanID: scan.id, status: 503))
        #expect(scan.scan.archiving?.state == .failed("Paperless is no longer connected."))
    }

    @Test func aScanWaitingForPaperlessIsNotDeletedByRetention() async throws {
        try connect()
        server.answer("GET", "/api/custom_fields/", "", status: 503)
        let scan = await readyScan()
        scan.markSent(.share)
        try await app.archive([scan])
        #expect(scan.scan.archiving?.state == .waiting("The server is not ready (error 503)."))
        app.path = []

        let later = AppModel(processor: fixture.processor, settings: fixture.settings, now: { .now.addingTimeInterval(2 * 86400) })
        #expect(later.scans.map(\.id) == [scan.id])
    }

    @Test func deletingAnOwnerForgetsItsToken() throws {
        let holding = try #require(fixture.settings.addOwner("Holding"))
        try connect(holding.id)

        app.deleteOwner(holding.id, movingScansTo: nil)
        #expect(tokens.token(for: holding.id) == nil)
    }

    private let taskID = Data(#""5f1c2a3e-0b9d-4c8e-9a61-2f7d3c4b5a6e""#.utf8)

    /// What Paperless-ngx answers to an upload it took: the ID of the task that consumes the document.
    private func taken(_ scan: ScanModel) -> UploadResult {
        UploadResult(scanID: scan.id, status: 200, body: taskID, url: uploader.uploads.last?.request.url, responseURL: uploader.uploads.last?.request.url)
    }

    /// The app model, archiver and uploader of the next launch, on the same scans, settings and tokens; a new uploader has no upload left.
    private func relaunch(uploader: FakeUploader = FakeUploader(), server: FakeServer? = nil) -> (AppModel, Archiver, FakeUploader) {
        let archiver = Archiver(uploader: uploader, tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: (server ?? self.server).fetch)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: archiver)
        return (app, archiver, uploader)
    }

    private func activate(_ app: AppModel, _ archiver: Archiver) async {
        app.setActive(true)
        await archiver.resuming?.value
    }

    private func uploadFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: fixture.root.appending(path: "Uploads").path(percentEncoded: false))) ?? []
    }
}

@MainActor
final class FakeUploader: Uploader {
    struct Upload {
        let request: URLRequest
        let body: Data
        let scanID: UUID
        let delay: Duration
    }

    var uploads: [Upload] = []
    var cancelled: [UUID] = []
    /// The scans whose upload was started and not cancelled; the fake never finishes one.
    var uploading: Set<UUID> = []

    func upload(_ request: URLRequest, fromFile file: URL, scanID: UUID, after delay: Duration) {
        uploads.append(Upload(request: request, body: (try? Data(contentsOf: file)) ?? Data(), scanID: scanID, delay: delay))
        uploading.insert(scanID)
    }

    func cancel(scanID: UUID) {
        cancelled.append(scanID)
        uploading.remove(scanID)
    }

    func uploadingScanIDs() async -> Set<UUID> {
        uploading
    }
}

final class MemoryTokens: PaperlessTokens {
    private let tokens = Mutex<[UUID: String]>([:])

    func token(for ownerID: UUID) -> String? {
        tokens.withLock { $0[ownerID] }
    }

    func setToken(_ token: String?, for ownerID: UUID) throws {
        tokens.withLock { $0[ownerID] = token }
    }

    func ownerIDs() -> Set<UUID> {
        tokens.withLock { Set($0.keys) }
    }
}

/// Answers the requests that prepare uploads with the answers queued for their method and path, 404 otherwise.
final class FakeServer: Sendable {
    private struct State {
        var answers: [String: [(status: Int, body: String, version: String?)]] = [:]
        var requests: [URLRequest] = []
        var delay: Duration = .zero
        var isHolding = false
        var held: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    var requests: [URLRequest] { state.withLock { $0.requests } }

    /// How long each answer takes.
    var delay: Duration {
        get { state.withLock { $0.delay } }
        set { state.withLock { $0.delay = newValue } }
    }

    /// Makes the requests wait for an answer until the returned closure is called.
    func hold() -> @Sendable () -> Void {
        state.withLock { $0.isHolding = true }
        return { [self] in
            let held = state.withLock { state in
                state.isHolding = false
                defer { state.held = [] }
                return state.held
            }
            held.forEach { $0.resume() }
        }
    }

    func waitUntilHolding(_ count: Int) async throws {
        while state.withLock({ $0.held.count }) < count { try await Task.sleep(for: .milliseconds(1)) }
    }

    func requests(to path: String) -> [URLRequest] {
        requests.filter { $0.url?.path() == path }
    }

    /// The version is the X-Version header Paperless-ngx adds to its answers.
    func answer(_ method: String, _ path: String, _ body: String, status: Int = 200, version: String? = nil) {
        state.withLock { $0.answers["\(method) \(path)", default: []].append((status, body, version)) }
    }

    var fetch: Archiver.Fetch {
        { [self] request in
            await withCheckedContinuation { continuation in
                let holds = state.withLock { state in
                    if state.isHolding { state.held.append(continuation) }
                    return state.isHolding
                }
                if !holds { continuation.resume() }
            }
            try await Task.sleep(for: delay)
            let answer = state.withLock { state in
                state.requests.append(request)
                let key = "\(request.httpMethod ?? "GET") \(request.url?.path() ?? "")"
                return state.answers[key]?.isEmpty == false ? state.answers[key]!.removeFirst() : (status: 404, body: "", version: nil)
            }
            let headers = answer.version.map { ["X-Version": $0] }
            return (Data(answer.body.utf8), HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: headers)!)
        }
    }
}
