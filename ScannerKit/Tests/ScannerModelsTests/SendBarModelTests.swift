import Foundation
import ScannerKit
import ScannerKitTesting
@testable import ScannerModels
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SendBarModelTests {
    let fixture: Fixture
    let app: AppModel
    let bar = SendBarModel()
    let sent = Sent()

    init() throws {
        fixture = try Fixture()
        app = AppModel(processor: fixture.processor, settings: fixture.settings)
    }

    /// The ways that went out, in order.
    @MainActor
    final class Sent {
        var methods: [SendMethod] = []
    }

    private func tap(_ method: SendMethod, _ scans: [ScanModel]) {
        bar.tap(method, scans: scans) { [sent] in sent.methods.append(method) }
    }

    /// Holds the PDF builds of the scan until `release` is called; `started` waits for the first build to start.
    private func holdPDF(of scan: ScanModel) -> (started: () async -> Void, release: () -> Void) {
        let (released, release) = AsyncStream<Void>.makeStream()
        let (started, start) = AsyncStream<Void>.makeStream()
        scan.makePDFData = { _ in
            start.finish()
            for await _ in released {}
            return Data("%PDF".utf8)
        }
        return ({ for await _ in started {} }, { release.finish() })
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        while !condition() { try await Task.sleep(for: .milliseconds(1)) }
    }

    @Test func waitsForThePDFThenSendsOnce() async throws {
        let scan = await fixture.capturedScan(in: app)
        let (_, release) = holdPDF(of: scan)
        tap(.share, [scan])
        #expect(bar.waiting == .share)
        try await Task.sleep(for: .milliseconds(50))
        #expect(sent.methods.isEmpty)

        release()
        try await waitUntil { !sent.methods.isEmpty }
        #expect(bar.waiting == nil)
        #expect(scan.hasCurrentPDF)
        try await Task.sleep(for: .milliseconds(50))
        #expect(sent.methods == [.share])
    }

    @Test func tappingTheWaitingButtonAgainCancelsAndAnotherButtonTakesItsPlace() async throws {
        let scan = await fixture.capturedScan(in: app)
        let (_, release) = holdPDF(of: scan)
        tap(.share, [scan])
        tap(.share, [scan])
        #expect(bar.waiting == nil)
        tap(.share, [scan])
        #expect(bar.waiting == .share)
        tap(.paperless, [scan])
        #expect(bar.waiting == .paperless)

        release()
        try await waitUntil { !sent.methods.isEmpty }
        try await Task.sleep(for: .milliseconds(50))
        #expect(sent.methods == [.paperless])
    }

    @Test func aCancelledWaitSendsNothing() async throws {
        let scan = await fixture.capturedScan(in: app)
        let (_, release) = holdPDF(of: scan)
        tap(.paperless, [scan])
        bar.cancel()
        #expect(bar.waiting == nil)
        release()
        await scan.preparePDF()
        try await Task.sleep(for: .milliseconds(50))
        #expect(sent.methods.isEmpty)
    }

    @Test func aDoubleTapStartsASingleSend() async throws {
        let scan = await fixture.capturedScan(in: app)
        await scan.preparePDF()
        tap(.paperless, [scan])
        #expect(bar.waiting == nil, "The PDF is ready: nothing to wait for")
        tap(.paperless, [scan])
        try await waitUntil { !sent.methods.isEmpty }
        try await Task.sleep(for: .milliseconds(50))
        #expect(sent.methods == [.paperless])
    }

    @Test func nothingStartsWhileASendRuns() async throws {
        let scan = await fixture.capturedScan(in: app)
        await scan.preparePDF()
        let (released, release) = AsyncStream<Void>.makeStream()
        let running = Sent()
        bar.tap(.paperless, scans: [scan]) {
            running.methods.append(.paperless)
            for await _ in released {}
        }
        try await waitUntil { bar.isSending }
        tap(.paperless, [scan])
        tap(.share, [scan])
        #expect(bar.waiting == nil)

        release.finish()
        try await waitUntil { !bar.isSending }
        try await Task.sleep(for: .milliseconds(50))
        #expect(running.methods == [.paperless])
        #expect(sent.methods.isEmpty)
        tap(.share, [scan])
        try await waitUntil { !sent.methods.isEmpty }
        #expect(sent.methods == [.share], "Another send starts once the first is done")
    }

    @Test func anEditWhileWaitingSendsTheEditedPDF() async throws {
        let scan = await fixture.capturedScan(in: app)
        let (started, release) = holdPDF(of: scan)
        tap(.share, [scan])
        await started()
        scan.rename("Water bill")
        release()
        try await waitUntil { !sent.methods.isEmpty }
        #expect(scan.hasCurrentPDF)
        #expect(fixture.pdfExists(scan.scan.name))
    }

    @Test(arguments: [false, true])
    func aPDFThatCannotBeMadeEndsTheWait(storageFull: Bool) async throws {
        let scan = await fixture.capturedScan(in: app)
        scan.makePDFData = { _ in throw storageFull ? POSIXError(.ENOSPC) : CocoaError(.fileWriteUnknown) }
        tap(.share, [scan])
        #expect(bar.waiting == .share)
        try await waitUntil { bar.waiting == nil }
        try await Task.sleep(for: .milliseconds(50))
        #expect(sent.methods.isEmpty)
        #expect(app.sendFooter(for: scan, waiting: bar.waiting).text == (storageFull ? "1 page · the iPhone storage is full" : "1 page · the PDF could not be made"))
    }

    @Test func nothingToSendWithoutScans() {
        tap(.share, [])
        #expect(bar.waiting == nil)
        #expect(!bar.isSending)
    }

    @Test func theFooterSaysWhatAWaitingButtonWillDo() async throws {
        let scan = await fixture.capturedScan(in: app)
        let other = await fixture.capturedScan(in: app)
        other.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await other.waitUntilIdle()
        #expect(app.sendFooter(for: scan, waiting: nil) == SendFooter(text: "1 page · preparing the PDF…"))
        #expect(app.sendFooter(for: scan, waiting: .share) == SendFooter(lead: "Share opens when the PDF is ready", text: "1 page"))
        #expect(app.sendFooter(for: other, waiting: .paperless) == SendFooter(lead: "Archives when the PDF is ready", text: "2 pages"))

        _ = fixture.settings.addOwner("Fernwood Holding")
        #expect(app.sendFooter(for: scan, waiting: nil) == SendFooter(text: "Me · 1 page · preparing the PDF…"))
        #expect(app.sendFooter(for: scan, waiting: .share) == SendFooter(lead: "Share opens when the PDF is ready", text: "1 page"))
    }

    @Test func namesArchiveAndWhereItSendsOnceConnected() async throws {
        let tokens = MemoryTokens()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: Archiver(uploader: FakeUploader(), tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: FakeServer().fetch))
        let scan = await fixture.capturedScan(in: app)
        #expect(app.sendButtons(for: scan) == SendButtons(named: .share, title: "Share", isProminent: false))
        #expect(app.destination(of: scan) == nil)
        #expect(app.sendFooter(for: scan, waiting: nil) == SendFooter(text: "1 page · preparing the PDF…", connectsPaperless: true))

        fixture.settings.value.defaultOwner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        #expect(!app.archives(scan), "Not connected without its token")
        try tokens.setToken("secret", for: scan.owner.id)
        #expect(app.sendButtons(for: scan) == SendButtons(named: .paperless, title: "Archive", isProminent: true, round: .share))
        #expect(app.sendFooter(for: scan, waiting: nil) == SendFooter(text: "To paperless.example.com · 1 page · preparing the PDF…"))
    }

    @Test func namesTheServerOfTheOwnerOfTheScan() async throws {
        let tokens = MemoryTokens()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: Archiver(uploader: FakeUploader(), tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: FakeServer().fetch))
        fixture.settings.value.defaultOwner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        try tokens.setToken("secret", for: fixture.settings.value.defaultOwnerID)
        var holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let mine = await fixture.capturedScan(in: app)
        let theirs = await fixture.capturedScan(in: app)
        theirs.setOwner(holding.id)
        #expect(app.sendFooter(for: mine, waiting: nil).text == "To paperless.example.com · 1 page · preparing the PDF…")
        #expect(app.sendFooter(for: theirs, waiting: nil) == SendFooter(text: "Fernwood Holding · 1 page · preparing the PDF…", connectsPaperless: true))
        #expect(app.ownerToConnect(for: theirs)?.id == holding.id)

        holding.paperless = PaperlessServer(url: URL(string: "https://archive.fernwood.example/")!)
        fixture.settings.value.updateOwner(holding)
        try tokens.setToken("secret", for: holding.id)
        #expect(app.destination(of: theirs) == "To archive.fernwood.example")
        #expect(app.sendFooter(for: theirs, waiting: nil) == SendFooter(text: "To archive.fernwood.example · 1 page · preparing the PDF…"))
    }

    private nonisolated static let now = Date(timeIntervalSince1970: 1_794_998_520)
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// An app whose clock reads 10:42 UTC, with the default owner connected to paperless.example.com.
    private func connectedApp() throws -> AppModel {
        let tokens = MemoryTokens()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: Archiver(uploader: FakeUploader(), tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: FakeServer().fetch), now: { Self.now })
        fixture.settings.value.defaultOwner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        try tokens.setToken("secret", for: fixture.settings.value.defaultOwnerID)
        return app
    }

    private func status(_ scan: ScanModel, in app: AppModel) -> SendStatus? {
        app.sendStatus(of: scan, calendar: Self.utc, locale: Locale(identifier: "en_GB"))
    }

    @Test func archiveSaysWhereTheUploadIs() async throws {
        let app = try connectedApp()
        let scan = await fixture.capturedScan(in: app)
        let archive = SendButtons(named: .paperless, title: "Archive", isProminent: true, round: .share)
        #expect(app.sendButtons(for: scan) == archive)
        #expect(status(scan, in: app) == nil)

        scan.setArchiving(Archiving())
        #expect(app.sendButtons(for: scan).title == "Try Now")
        #expect(status(scan, in: app) == SendStatus(kind: .uploading, text: "Archiving to paperless.example.com…"))
        scan.setArchiving(Archiving(state: .waiting("The server is not ready (error 503).")))
        #expect(app.sendButtons(for: scan) == SendButtons(named: .paperless, title: "Try Now", isProminent: true, round: .share))
        #expect(status(scan, in: app) == SendStatus(kind: .uploading, text: "Waiting for paperless.example.com"))
        scan.setArchiving(Archiving(state: .failed("The token was refused.")))
        #expect(app.sendButtons(for: scan) == SendButtons(named: .paperless, title: "Try Again", isProminent: true, round: .share))
        #expect(status(scan, in: app) == SendStatus(kind: .failed, text: "Not archived: The token was refused."))

        scan.setArchiving(nil)
        #expect(app.sendButtons(for: scan).title == "Archive")
    }

    @Test func anArchivedScanCanBeArchivedAgain() async throws {
        let app = try connectedApp()
        let scan = await fixture.capturedScan(in: app)
        scan.markSent(.paperless)
        #expect(app.sendButtons(for: scan) == SendButtons(named: .paperless, title: "Archive", isProminent: true, round: .share))
        #expect(status(scan, in: app) == SendStatus(kind: .sent, text: "Archived to paperless.example.com · 10:42"))

        scan.markSent(.share)
        #expect(scan.scan.sent == ScannerKit.Sent(date: Self.now, method: .paperless), "Sharing an archived scan keeps it archived")
    }

    @Test func aSharedScanCanStillBeArchived() async throws {
        let app = try connectedApp()
        let scan = await fixture.capturedScan(in: app)
        app.didSend([scan], by: .share)
        #expect(app.sendButtons(for: scan).named == .paperless)
        #expect(status(scan, in: app) == SendStatus(kind: .sent, text: "Shared · 10:42"))
    }

    @Test(arguments: [
        (0.0, "10:42"),
        (-10.0, "0:42"),
        (-11.0, "yesterday 23:42"),
        (-30.0, "yesterday 4:42"),
        (-60.0, "15 Nov 22:42"),
    ])
    func timesWhenTheScanWentOut(hours: Double, time: String) {
        #expect(Self.now.addingTimeInterval(hours * 3600).shortTime(now: Self.now, calendar: Self.utc, locale: Locale(identifier: "en_GB")) == time)
    }

    @Test func aSentScanTellsWhenItLeaves() async throws {
        let clock = TestClock(Self.now)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: clock.now)
        let scan = await fixture.capturedScan(in: app)
        let footer = { app.sendFooter(for: scan, waiting: nil, calendar: Self.utc, locale: Locale(identifier: "en_GB")) }
        app.didSend([scan], by: .share)
        #expect(footer() == SendFooter(text: "Leaves this iPhone tomorrow at 10:42"))
        clock.advance(hours: 14)
        #expect(footer() == SendFooter(text: "Leaves this iPhone today at 10:42"))
        clock.advance(hours: 11)
        #expect(footer() == SendFooter(text: "Leaves this iPhone soon"))
        #expect(app.sendFooter(for: scan, waiting: .share) == SendFooter(lead: "Share opens when the PDF is ready", text: "1 page"))
    }

    @Test func offersToConnectPaperlessForTheOwnerOfTheScan() async throws {
        let app = try connectedApp()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let scan = await fixture.capturedScan(in: app)
        scan.setOwner(holding.id)
        #expect(app.ownerToConnect(for: scan)?.id == holding.id)
        #expect(app.sendFooter(for: scan, waiting: nil) == SendFooter(text: "Fernwood Holding · 1 page · preparing the PDF…", connectsPaperless: true))
    }

    @Test func homeOffersToArchiveOrShareEachScan() async throws {
        let app = try connectedApp()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let scan = await fixture.capturedScan(in: app)
        #expect(app.swipeActions(for: scan.scan) == [.archive, .share])
        #expect([RowAction.archive, .tryAgain, .share].map(\.title) == ["Archive", "Try Again", "Share"])

        scan.setArchiving(Archiving(state: .waiting("The server is not ready (error 503).")))
        #expect(app.swipeActions(for: scan.scan).isEmpty, "Nothing while it is on its way to Paperless")
        scan.setArchiving(Archiving(state: .failed("The token was refused.")))
        #expect(app.swipeActions(for: scan.scan) == [.tryAgain, .share])
        scan.setArchiving(nil)
        scan.markSent(.paperless)
        #expect(app.swipeActions(for: scan.scan) == [.archive, .share], "An archived scan can be archived again")

        let shared = await fixture.capturedScan(in: app)
        app.didSend([shared], by: .share)
        #expect(app.swipeActions(for: shared.scan) == [.archive, .share], "A shared scan can still be archived")

        let theirs = await fixture.capturedScan(in: app)
        theirs.setOwner(holding.id)
        #expect(app.swipeActions(for: theirs.scan) == [.share])
        theirs.setArchiving(Archiving(state: .failed("Paperless is no longer connected.")))
        #expect(app.swipeActions(for: theirs.scan) == [.share])
    }

    @Test func homeSendsEveryScanNotSentInOneTap() async throws {
        let app = try connectedApp()
        let first = await fixture.capturedScan(in: app)
        first.rename("Water bill")
        #expect(app.notSentOffer == nil, "Only with more than one scan")
        let second = await fixture.capturedScan(in: app)
        second.rename("Gas bill")
        second.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await second.waitUntilIdle()
        #expect(app.notSentOffer == NotSentOffer(scans: [first.scan, second.scan], archives: true, title: "2 scans not sent", subtitle: "3 pages · to Paperless", button: "Archive All"))

        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        second.setOwner(holding.id)
        #expect(app.notSentOffer == NotSentOffer(scans: [first.scan, second.scan], archives: false, title: "2 scans not sent", subtitle: "Water bill, Gas bill", button: "Share All"))

        app.didSend([first], by: .share)
        #expect(app.notSentOffer == nil)
    }
}
