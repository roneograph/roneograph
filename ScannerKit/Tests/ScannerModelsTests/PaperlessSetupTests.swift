import Foundation
import ScannerKit
@testable import ScannerModels
import Synchronization
import Testing

@MainActor
struct PaperlessSetupTests {
    let fixture: Fixture
    let tokens = MemoryTokens()
    let archiver: Archiver
    let requests = RequestLog()

    init() throws {
        fixture = try Fixture()
        archiver = Archiver(uploader: FakeUploader(), tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: FakeServer().fetch)
    }

    private func setup(_ ownerID: UUID? = nil, status: Int = 200, body: String = #"{"results": [{"id": 1, "name": "Personal"}, {"id": 2, "name": "Holding"}]}"#) -> PaperlessSetup {
        let requests = requests
        return PaperlessSetup(ownerID: ownerID ?? fixture.settings.value.defaultOwnerID, settings: fixture.settings, archiver: archiver) { request in
            requests.append(request)
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func connectsWithTheAddressAndTokenThenKeepsTheStoragePathPicked() async throws {
        let setup = setup()
        setup.address = "paperless.example.com"
        setup.token = " secret "

        await setup.connect()
        #expect(setup.state == .connected([PaperlessStoragePath(id: 1, name: "Personal"), PaperlessStoragePath(id: 2, name: "Holding")]))
        #expect(requests.all.first?.value(forHTTPHeaderField: "Authorization") == "Token secret")

        setup.storagePath = PaperlessStoragePath(id: 2, name: "Holding")
        try setup.save()
        let owner = fixture.settings.value.defaultOwner
        #expect(owner.paperless == PaperlessServer(url: URL(string: "https://paperless.example.com/")!, storagePath: PaperlessStoragePath(id: 2, name: "Holding")))
        #expect(tokens.token(for: owner.id) == "secret")
        #expect(archiver.isConnected(owner))
    }

    @Test func tellsWhyTheServerCannotBeUsed() async {
        let setup = setup(status: 401)
        setup.address = "https://paperless.example.com"
        setup.token = "wrong"

        await setup.connect()
        #expect(setup.state == .failed("The server refused the token."))
    }

    @Test func tellsWhenTheServerCannotBeReached() async {
        let setup = PaperlessSetup(ownerID: fixture.settings.value.defaultOwnerID, settings: fixture.settings, archiver: archiver) { _ in
            throw URLError(.cannotFindHost)
        }
        setup.address = "https://paperless.example.com"
        setup.token = "secret"

        await setup.connect()
        #expect(setup.state == .failed("The server cannot be found."))
    }

    @Test func refusesAnAddressThatIsNotHTTPSWithoutAsking() async {
        let setup = setup()
        setup.address = "http://192.168.1.10:8000"
        setup.token = "secret"

        await setup.connect()
        #expect(setup.state == .failed("Type the address of the server, such as https://paperless.example.com."))
        #expect(requests.all.isEmpty)
    }

    @Test func savesNothingUntilConnectedWithWhatIsTyped() async throws {
        let setup = setup()
        setup.address = "paperless.example.com"
        setup.token = "secret"
        await setup.connect()

        setup.token = "other"
        #expect(setup.state == .idle)
        try setup.save()
        #expect(fixture.settings.value.defaultOwner.paperless == nil)
    }

    @Test func startsFromTheServerOfAnotherOwner() async throws {
        let personal = setup()
        personal.address = "paperless.example.com"
        personal.token = "secret"
        await personal.connect()
        personal.storagePath = PaperlessStoragePath(id: 1, name: "Personal")
        try personal.save()
        let holding = try #require(fixture.settings.addOwner("Holding"))

        let setup = setup(holding.id)
        #expect(setup.address == "https://paperless.example.com/")
        #expect(setup.token == "secret")
        #expect(setup.storagePath == nil)
    }

    @Test func dropsAStoragePathGoneFromTheServer() async throws {
        var owner = fixture.settings.value.defaultOwner
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!, storagePath: PaperlessStoragePath(id: 9, name: "Old"))
        fixture.settings.value.updateOwner(owner)
        try tokens.setToken("secret", for: owner.id)
        let setup = setup()
        #expect(setup.storagePath?.id == 9)

        await setup.connect()
        #expect(setup.storagePath == nil)
    }

    @Test func listsTheStoragePathsOfAnOwnerAlreadyConnectedWithoutConnectingAgain() async throws {
        try connectDefaultOwner(storagePath: PaperlessStoragePath(id: 1, name: "Personal"))
        let setup = setup()
        #expect(!setup.hasChanges)

        await setup.connectToSavedServer()
        #expect(setup.state == .connected([PaperlessStoragePath(id: 1, name: "Personal"), PaperlessStoragePath(id: 2, name: "Holding")]))
        #expect(requests.all.first?.value(forHTTPHeaderField: "Authorization") == "Token secret")
        #expect(!setup.hasChanges)

        setup.storagePath = PaperlessStoragePath(id: 2, name: "Holding")
        #expect(setup.hasChanges)
        try setup.save()
        #expect(fixture.settings.value.defaultOwner.paperless?.storagePath == PaperlessStoragePath(id: 2, name: "Holding"))
        #expect(!setup.hasChanges)
    }

    @Test func waitsForConnectWhenTheOwnerIsNotConnected() async throws {
        try connectDefaultOwner()
        try tokens.setToken(nil, for: fixture.settings.value.defaultOwnerID)
        let holding = try #require(fixture.settings.addOwner("Holding"))
        try tokens.setToken("secret", for: holding.id)

        for ownerID in [fixture.settings.value.defaultOwnerID, holding.id] {
            let setup = setup(ownerID)
            await setup.connectToSavedServer()
            #expect(setup.state == .idle)
        }
        #expect(requests.all.isEmpty)
    }

    @Test func needsToConnectAgainOnceTheAddressOrTokenChanges() async throws {
        try connectDefaultOwner()
        let setup = setup()
        await setup.connectToSavedServer()

        setup.address = "paperless.example.org"
        #expect(setup.state == .idle)
        #expect(!setup.hasChanges)
        try setup.save()
        #expect(fixture.settings.value.defaultOwner.paperless?.url == URL(string: "https://paperless.example.com/"))

        await setup.connect()
        try setup.save()
        #expect(fixture.settings.value.defaultOwner.paperless?.url == URL(string: "https://paperless.example.org/"))
    }

    @Test func ignoresAnAnswerForATokenNoLongerTyped() async throws {
        try connectDefaultOwner()
        let typing = Typing()
        let setup = PaperlessSetup(ownerID: fixture.settings.value.defaultOwnerID, settings: fixture.settings, archiver: archiver) { request in
            await typing.type()
            return (Data(#"{"results": []}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        typing.setup = setup

        await setup.connectToSavedServer()
        #expect(setup.token == "other")
        #expect(setup.state == .idle)
    }

    private func connectDefaultOwner(storagePath: PaperlessStoragePath? = nil) throws {
        var owner = fixture.settings.value.defaultOwner
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!, storagePath: storagePath)
        fixture.settings.value.updateOwner(owner)
        try tokens.setToken("secret", for: owner.id)
    }

    @Test func disconnectingForgetsTheServerAndToken() async throws {
        let setup = setup()
        setup.address = "paperless.example.com"
        setup.token = "secret"
        await setup.connect()
        try setup.save()
        let ownerID = fixture.settings.value.defaultOwnerID

        PaperlessSetup.disconnect(ownerID, settings: fixture.settings, archiver: archiver)
        #expect(fixture.settings.value.defaultOwner.paperless == nil)
        #expect(tokens.token(for: ownerID) == nil)
    }
}

@MainActor
private final class Typing {
    var setup: PaperlessSetup?

    func type() {
        setup?.token = "other"
    }
}

final class RequestLog: Sendable {
    private let requests = Mutex<[URLRequest]>([])

    var all: [URLRequest] { requests.withLock { $0 } }

    func append(_ request: URLRequest) {
        requests.withLock { $0.append(request) }
    }
}
