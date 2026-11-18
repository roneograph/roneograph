import Foundation
import ScannerKit
import ScannerKitTesting
@testable import ScannerModels
import Synchronization
import Testing

/// How the app model keeps each scan with its pages until it is sent.
@MainActor
@Suite(.serialized)
struct ScanKeepingTests {
    @Test func pagesAddedAfterSendingAreNotSentAndAreNotDeletedByRetention() async throws {
        let fixture = try Fixture()
        let clock = TestClock()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: clock.now)
        let scan = await fixture.capturedScan(in: app)
        app.didSend([scan], by: .email)
        clock.advance(days: 8)

        app.continueScan(scan.id)
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await scan.waitUntilIdle()
        app.finishCapture(scan)
        app.path = []
        app.refresh()

        #expect(app.scans.map(\.id) == [scan.id])
        #expect(app.scans.first?.status == "Not sent · now · 2 pages")
        #expect(app.notSent.map(\.id) == [scan.id])
        #expect(fixture.store.all().first?.sent == nil)
    }

    @Test func pagesAddedWhileArchivingStopTheUpload() async throws {
        let fixture = try Fixture()
        let uploader = FakeUploader()
        let tokens = MemoryTokens()
        let archiver = Archiver(uploader: uploader, tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: FakeServer().fetch)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: archiver)
        fixture.settings.value.defaultOwner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        try tokens.setToken("secret", for: fixture.settings.value.defaultOwnerID)
        let scan = await fixture.capturedScan(in: app)
        await scan.preparePDF()
        try await app.archive([scan])
        try #require(uploader.uploads.map(\.scanID) == [scan.id])

        app.continueScan(scan.id)
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        #expect(uploader.cancelled == [scan.id])
        #expect(scan.scan.archiving == nil)
        await scan.waitUntilIdle()
        app.finishCapture(scan)

        archiver.complete(UploadResult(scanID: scan.id, status: 200))
        #expect(scan.scan.sent == nil)
        #expect(app.notSent.map(\.id) == [scan.id])
    }
}

/// A clock the tests move forward.
final class TestClock: Sendable {
    private let date = Mutex(Date())

    var now: @Sendable () -> Date { { self.date.withLock { $0 } } }

    func advance(days: Double) {
        date.withLock { $0.addTimeInterval(days * 86400) }
    }
}
