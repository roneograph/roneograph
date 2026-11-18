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
        #expect(app.sendFooter(for: [scan], waiting: bar.waiting, summary: scan.summary).text == (storageFull ? "1 page · the iPhone storage is full" : "1 page · the PDF could not be made"))
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
        #expect(app.sendFooter(for: [scan], waiting: nil, summary: scan.summary) == SendFooter(text: "1 page · preparing the PDF…"))
        #expect(app.sendFooter(for: [scan], waiting: .share, summary: scan.summary) == SendFooter(lead: "Share opens when the PDF is ready", text: "1 page"))
        #expect(app.sendFooter(for: [scan, other], waiting: .paperless, summary: [scan, other].selectionSummary) == SendFooter(lead: "Archives when the PDFs are ready", text: "3 pages"))

        _ = fixture.settings.addOwner("Fernwood Holding")
        #expect(app.sendFooter(for: [scan], waiting: nil, summary: scan.summary) == SendFooter(text: "Me · 1 page · preparing the PDF…"))
        #expect(app.sendFooter(for: [scan], waiting: .share, summary: scan.summary) == SendFooter(lead: "Share opens when the PDF is ready", text: "1 page"))
    }

    @Test func namesArchiveAndWhereItSendsOnceConnected() async throws {
        let tokens = MemoryTokens()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: Archiver(uploader: FakeUploader(), tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: FakeServer().fetch))
        let scan = await fixture.capturedScan(in: app)
        let footer = { app.sendFooter(for: [scan], waiting: nil, summary: scan.summary).text }
        #expect(app.namedSendMethod(for: [scan]) == nil, "Share is never named")
        #expect(app.destination(of: [scan]) == nil)
        #expect(footer() == "1 page · preparing the PDF…")

        fixture.settings.value.defaultOwner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        #expect(app.namedSendMethod(for: [scan]) == nil, "Not connected without its token")
        try tokens.setToken("secret", for: scan.owner.id)
        #expect(app.namedSendMethod(for: [scan]) == .paperless)
        #expect(footer() == "To paperless.example.com · 1 page · preparing the PDF…")
    }

    @Test func namesTheDestinationOnlyWhenTheScansHaveOneOwner() async throws {
        let tokens = MemoryTokens()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: Archiver(uploader: FakeUploader(), tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: FakeServer().fetch))
        fixture.settings.value.defaultOwner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        try tokens.setToken("secret", for: fixture.settings.value.defaultOwnerID)
        var holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let mine = await fixture.capturedScan(in: app)
        let theirs = await fixture.capturedScan(in: app)
        theirs.setOwner(holding.id)
        #expect(app.namedSendMethod(for: [mine, theirs]) == nil, "Fernwood Holding is not connected")
        #expect(app.sendFooter(for: [mine], waiting: nil, summary: "1 page").text == "To paperless.example.com · 1 page")
        #expect(app.sendFooter(for: [theirs], waiting: nil, summary: "1 page").text == "Fernwood Holding · 1 page")

        holding.paperless = PaperlessServer(url: URL(string: "https://archive.fernwood.example/")!)
        fixture.settings.value.updateOwner(holding)
        try tokens.setToken("secret", for: holding.id)
        #expect(app.namedSendMethod(for: [mine, theirs]) == .paperless)
        #expect(app.destination(of: [mine, theirs]) == nil)
        #expect(app.sendFooter(for: [mine, theirs], waiting: nil, summary: "2 documents · 2 pages").text == "2 owners · 2 documents · 2 pages")
        #expect(app.sendFooter(for: [theirs], waiting: nil, summary: "1 page").text == "To archive.fernwood.example · 1 page")
        #expect(app.namedSendMethod(for: []) == .paperless, "Every owner when none is selected")
        #expect(app.destination(of: []) == nil)
    }
}
