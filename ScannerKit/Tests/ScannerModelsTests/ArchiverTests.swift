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

    @Test func showsArchiveAndEmailOnlyWhenEveryOwnerOfTheScansHasThem() async throws {
        let holding = try #require(fixture.settings.addOwner("Holding"))
        let personal = await readyScan()
        let company = await readyScan()
        company.setOwner(holding.id)
        #expect(app.sendMethods(for: [personal]) == [.files, .share])

        try connect()
        fixture.settings.value.defaultOwner.email = "me@example.com"
        #expect(app.sendMethods(for: [personal]) == [.paperless, .email, .files, .share])
        #expect(app.sendMethods(for: [personal, company]) == [.files, .share])
        #expect(app.sendMethods(for: []) == [.files, .share], "With nothing selected, every owner counts")

        try connect(holding.id)
        #expect(app.sendMethods(for: [personal, company]) == [.paperless, .files, .share])
        #expect(app.sendMethods(for: []) == [.paperless, .files, .share])
    }

    @Test func hidesArchiveWhenTheTokenIsMissing() async throws {
        let scan = await readyScan()
        var owner = scan.owner
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        fixture.settings.value.updateOwner(owner)
        #expect(!app.sendMethods(for: [scan]).contains(.paperless))
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
        #expect(server.requests.map(\.httpMethod) == ["GET"], "The types are read once")
    }

    @Test func createsTheDocumentTypeOfANewCategory() async throws {
        try connect()
        server.answer("GET", "/api/document_types/", #"{"results": []}"#)
        server.answer("POST", "/api/document_types/", #"{"id": 8, "name": "Payslip"}"#, status: 201)
        let scan = await readyScan()
        scan.setDetails(DocumentDetails(category: .payslip))
        await scan.preparePDF()

        try await app.archive([scan])
        let created = try #require(server.requests.last)
        #expect(String(decoding: created.httpBody ?? Data(), as: UTF8.self) == #"{"matching_algorithm":0,"name":"Payslip"}"#)
        #expect(String(decoding: try #require(uploader.uploads.first).body, as: UTF8.self).contains("name=\"document_type\"\r\n\r\n8\r\n"))
    }

    @Test func sendsOtherDocumentsWithoutAType() async throws {
        try connect()
        let scan = await readyScan()

        try await app.archive([scan])
        #expect(server.requests.isEmpty)
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
        await app.archiver?.prepareWaitingUploads()
        #expect(uploader.uploads.count == 1)
        #expect(scan.scan.archiving == Archiving())
    }

    @Test func aScanIsSentOnceTheServerTookIt() async throws {
        try connect()
        let scan = await readyScan()
        try await app.archive([scan])

        app.archiver?.complete(UploadResult(scanID: scan.id, status: 200))
        #expect(scan.scan.sent?.method == .paperless)
        #expect(scan.scan.archiving == nil)
        #expect(uploadFiles().isEmpty)
        #expect(app.scans.first?.status.hasPrefix("Archived") == true)
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
        app.archiver?.complete(UploadResult(scanID: scan.id, status: 201))
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

        app.archiver?.complete(UploadResult(scanID: scan.id, status: 200))
        #expect(scan.scan.sent == nil)
        app.setActive(true)
        #expect(scan.scan.sent?.method == .paperless)
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
        let scan = await readyScan()
        try await app.archive([scan])
        fixture.settings.value.keepScans = .day
        app.path = []

        let later = AppModel(processor: fixture.processor, settings: fixture.settings, now: { .now.addingTimeInterval(400 * 86400) })
        #expect(later.scans.map(\.id) == [scan.id])
    }

    @Test func deletingAnOwnerForgetsItsToken() throws {
        let holding = try #require(fixture.settings.addOwner("Holding"))
        try connect(holding.id)

        app.deleteOwner(holding.id, movingScansTo: nil)
        #expect(tokens.token(for: holding.id) == nil)
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

    func upload(_ request: URLRequest, fromFile file: URL, scanID: UUID, after delay: Duration) {
        uploads.append(Upload(request: request, body: (try? Data(contentsOf: file)) ?? Data(), scanID: scanID, delay: delay))
    }

    func cancel(scanID: UUID) {
        cancelled.append(scanID)
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
        var answers: [String: [(status: Int, body: String)]] = [:]
        var requests: [URLRequest] = []
    }

    private let state = Mutex(State())

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func answer(_ method: String, _ path: String, _ body: String, status: Int = 200) {
        state.withLock { $0.answers["\(method) \(path)", default: []].append((status, body)) }
    }

    var fetch: Archiver.Fetch {
        { [self] request in
            let answer = state.withLock { state in
                state.requests.append(request)
                let key = "\(request.httpMethod ?? "GET") \(request.url?.path() ?? "")"
                return state.answers[key]?.isEmpty == false ? state.answers[key]!.removeFirst() : (status: 404, body: "")
            }
            return (Data(answer.body.utf8), HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
