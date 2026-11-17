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
        tap(.email, [scan])
        #expect(bar.waiting == .email)
        try await Task.sleep(for: .milliseconds(50))
        #expect(sent.methods.isEmpty)

        release()
        try await waitUntil { !sent.methods.isEmpty }
        #expect(bar.waiting == nil)
        #expect(scan.hasCurrentPDF)
        try await Task.sleep(for: .milliseconds(50))
        #expect(sent.methods == [.email])
    }

    @Test func tappingTheWaitingButtonAgainCancelsAndAnotherButtonTakesItsPlace() async throws {
        let scan = await fixture.capturedScan(in: app)
        let (_, release) = holdPDF(of: scan)
        tap(.email, [scan])
        tap(.email, [scan])
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
        tap(.files, [scan])
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
        tap(.email, [scan])
        #expect(bar.waiting == nil)

        release.finish()
        try await waitUntil { !bar.isSending }
        try await Task.sleep(for: .milliseconds(50))
        #expect(running.methods == [.paperless])
        #expect(sent.methods.isEmpty)
        tap(.email, [scan])
        try await waitUntil { !sent.methods.isEmpty }
        #expect(sent.methods == [.email], "Another send starts once the first is done")
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
        #expect(fixture.pdfExists(scan.scan.fileName))
    }

    @Test(arguments: [false, true])
    func aPDFThatCannotBeMadeEndsTheWait(storageFull: Bool) async throws {
        let scan = await fixture.capturedScan(in: app)
        scan.makePDFData = { _ in throw storageFull ? POSIXError(.ENOSPC) : CocoaError(.fileWriteUnknown) }
        tap(.email, [scan])
        #expect(bar.waiting == .email)
        try await waitUntil { bar.waiting == nil }
        try await Task.sleep(for: .milliseconds(50))
        #expect(sent.methods.isEmpty)
        #expect(app.sendFooter(for: [scan], waiting: bar.waiting, summary: scan.summary).text == (storageFull ? "1 page · the iPhone storage is full" : "1 page · the PDF could not be made"))
    }

    @Test func nothingToSendWithoutScans() {
        tap(.email, [])
        #expect(bar.waiting == nil)
        #expect(!bar.isSending)
    }

    @Test func theFooterSaysWhatAWaitingButtonWillDo() async throws {
        let scan = await fixture.capturedScan(in: app)
        let other = await fixture.capturedScan(in: app)
        other.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await other.waitUntilIdle()
        #expect(app.sendFooter(for: [scan], waiting: nil, summary: scan.summary) == SendFooter(text: "1 page · preparing the PDF…"))
        #expect(app.sendFooter(for: [scan], waiting: .email, summary: scan.summary) == SendFooter(lead: "Email opens when the PDF is ready", text: "1 page"))
        #expect(app.sendFooter(for: [scan], waiting: .share, summary: scan.summary).lead == "Share opens when the PDF is ready")
        #expect(app.sendFooter(for: [scan], waiting: .files, summary: scan.summary).lead == "Saves when the PDF is ready")
        #expect(app.sendFooter(for: [scan, other], waiting: .paperless, summary: [scan, other].selectionSummary) == SendFooter(lead: "Archives when the PDFs are ready", text: "3 pages"))

        _ = fixture.settings.addOwner("Fernwood Holding")
        #expect(app.sendFooter(for: [scan], waiting: nil, summary: scan.summary) == SendFooter(text: "Me · 1 page · preparing the PDF…"))
        #expect(app.sendFooter(for: [scan], waiting: .email, summary: scan.summary) == SendFooter(lead: "Email opens when the PDF is ready", text: "1 page"))
    }
}
