import CoreImage
import Foundation
import ScannerKit
import ScannerKitTesting
@testable import ScannerModels
import Testing

@MainActor
@Suite(.serialized)
struct AppModelTests {
    @Test func startsWithNoScansAndOpensTheCameraOnScan() throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        #expect(app.scans.isEmpty)
        let scan = app.startScan()
        #expect(app.camera === scan)
        #expect(app.scans.isEmpty)
    }

    @Test func closingTheCameraWithoutPagesLeavesNoScan() throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        app.startScan()
        app.closeCamera()
        #expect(app.camera == nil)
        #expect(app.scans.isEmpty)
    }

    @Test func closingTheCameraKeepsAScanInProgress() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = app.startScan()
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await scan.waitUntilIdle()
        app.closeCamera()

        #expect(app.scans.map(\.id) == [scan.id])
        #expect(app.scans.first?.isFinished == false)
        #expect(app.path.isEmpty)
    }

    @Test func closingTheCameraWhileAPageIsProcessedKeepsTheScan() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = app.startScan()
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        app.closeCamera()
        #expect(app.model(for: scan.id) === scan)

        await scan.waitUntilIdle()
        #expect(app.scans.map(\.id) == [scan.id])
    }

    @Test func deletingTheOnlyPageInTheCameraLeavesNoScan() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = app.startScan()
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await scan.waitUntilIdle()
        scan.deleteCapturedPage(scan.scan.pages[0].id)
        await scan.waitUntilIdle()
        app.closeCamera()

        #expect(app.scans.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func makesThePagesCapturedBeforeTheAppWasQuitOnTheNextLaunch() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let release = await fixture.holdGate()
        let scan = app.startScan()
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        scan.addPhoto(SyntheticPhoto.jpeg(page: .rect(x: 0.2, y: 0.1, width: 0.6, height: 0.6)), liveQuad: nil)
        let captured = scan.scan.pending.map(\.id)

        let relaunched = AppModel(processor: ScanProcessor(store: fixture.store, paper: .a4), settings: fixture.settings)
        while fixture.store.all().first?.pages.count != 2 { try await Task.sleep(for: .milliseconds(10)) }
        let stored = try #require(fixture.store.all().first)
        #expect(stored.pages.map(\.id) == captured)
        #expect(stored.pending.isEmpty)
        #expect(stored.pages[1].quad.map { $0.maxCornerDistance(to: .rect(x: 0.2, y: 0.1, width: 0.6, height: 0.6)) < 0.02 } == true)
        for page in stored.pages {
            #expect(FileManager.default.fileExists(atPath: fixture.store.previewURL(scanID: scan.id, pageID: page.id).path(percentEncoded: false)))
        }
        let resumed = try #require(relaunched.model(for: scan.id))
        await resumed.waitUntilIdle()
        #expect(resumed.scan.pages == stored.pages)

        scan.delete()
        await release()
    }

    @Test(.timeLimit(.minutes(1)))
    func pagesAndPDFsWaitWhileTheAppIsNotActive() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let built = await fixture.capturedScan(in: app)
        app.setActive(false)
        let scan = app.startScan()
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        let build = Task { await built.buildPDF(delay: .zero) }
        try await fixture.waitUntilGateHasWaiting(2)
        #expect(scan.scan.pages.isEmpty)
        #expect(!fixture.pdfExists(built.scan.name))

        app.setActive(true)
        await scan.waitUntilIdle()
        await build.value
        #expect(scan.scan.pages.count == 1)
        #expect(built.hasCurrentPDF)
    }

    @Test func asksForAFailedPDFAgainOnceTheAppIsActiveAgain() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        let makePDFData = scan.makePDFData
        scan.makePDFData = { _ in throw POSIXError(.ENOSPC) }
        await scan.buildPDF(delay: .zero)
        try #require(scan.pdf == .storageFull)
        let failed = scan.pdfRequest

        app.setActive(false)
        #expect(scan.pdfRequest == failed)
        scan.makePDFData = makePDFData
        app.setActive(true)
        #expect(scan.pdfRequest != failed)
        await scan.buildPDF(delay: .zero)
        #expect(scan.hasCurrentPDF)

        let built = scan.pdfRequest
        app.setActive(false)
        app.setActive(true)
        #expect(scan.pdfRequest == built)
    }

    @Test func keepsTheListCurrentFromSavesWithoutReadingTheStoreAgain() async throws {
        let fixture = try Fixture()
        var old = Scan(created: Date().addingTimeInterval(-3600), name: "Old")
        old.pages = [ScanPage(quad: nil, analysis: .sample)]
        try fixture.store.save(old)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        var elsewhere = Scan(name: "Elsewhere")
        elsewhere.pages = [ScanPage(quad: nil, analysis: .sample)]
        try fixture.store.save(elsewhere)

        let scan = app.startScan()
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await scan.waitUntilIdle()
        try #require(app.model(for: old.id)).rename("Water bill")
        #expect(app.scans.map(\.id) == [scan.id, old.id])
        #expect(app.scans.first == scan.scan)
        #expect(app.scans.last?.name == "Water bill")

        scan.deleteCapturedPage(scan.scan.pages[0].id)
        await scan.waitUntilIdle()
        #expect(app.scans.map(\.id) == [old.id])

        app.refresh()
        #expect(app.scans.map(\.id) == [elsewhere.id, old.id])
    }

    @Test func namesAvoidTheOtherScansAndTheFilesInDocuments() async throws {
        let fixture = try Fixture()
        var stored = Scan(name: "Letter")
        stored.pages = [ScanPage(quad: nil, analysis: .sample)]
        try fixture.store.save(stored)
        try Data().write(to: fixture.store.documentsDirectory.appending(path: "Receipt.pdf"))
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let first = await fixture.capturedScan(in: app)
        let second = await fixture.capturedScan(in: app)

        first.rename("Invoice")
        second.rename("invoice")
        #expect(second.scan.name == "invoice 2")
        first.rename("Invoice")
        #expect(first.scan.name == "Invoice")
        first.rename("Letter")
        #expect(first.scan.name == "Letter 2")
        second.rename("Receipt")
        #expect(second.scan.name == "Receipt 2")
    }

    @Test func aNewFileNameFormatRenamesTheScansOfItsOwnerNotSentYet() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let waiting = await fixture.capturedScan(in: app)
        waiting.rename("Water bill")
        await waiting.preparePDF()
        let sent = await fixture.capturedScan(in: app)
        sent.rename("Gas bill")
        app.didSend([sent], by: .share)
        let other = await fixture.capturedScan(in: app)
        other.rename("Payslip")
        other.setOwner(holding.id)
        let reviewed = await fixture.capturedScan(in: app)
        reviewed.rename("Rent receipt")
        app.didSend([reviewed], by: .share)
        app.path = [reviewed.id]

        fixture.settings.value.defaultOwner.fileNameFormat.separator = .underscore
        #expect(waiting.scan.name == "Water_bill")
        #expect(fixture.pdfExists("Water_bill"))
        #expect(!fixture.pdfExists("Water bill"))
        #expect(!waiting.hasCurrentPDF)
        #expect(reviewed.scan.name == "Rent_receipt")
        #expect(sent.scan.name == "Gas bill")
        #expect(other.scan.name == "Payslip")
        #expect(Set(fixture.store.all().map(\.name)) == ["Water_bill", "Rent_receipt", "Gas bill", "Payslip"])
    }

    @Test func leavingTheForegroundSavesTheSettingsAtOnce() throws {
        let fixture = try Fixture()
        let settings = SettingsStore(defaults: fixture.defaults, saveDelay: .seconds(3600))
        let app = AppModel(processor: fixture.processor, settings: settings)
        settings.value.autoCapture = false
        #expect(SettingsStore(defaults: fixture.defaults).value.autoCapture)

        app.setActive(false)
        #expect(!SettingsStore(defaults: fixture.defaults).value.autoCapture)
    }

    @Test func doneOpensReview() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = app.startScan()
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await scan.waitUntilIdle()
        app.finishCapture(scan)

        #expect(app.camera == nil)
        #expect(app.path == [scan.id])
        #expect(app.scans.first?.isFinished == true)
    }

    @Test func aNewScanFromReviewReplacesItWhenDone() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let first = await fixture.capturedScan(in: app)
        let second = await fixture.capturedScan(in: app)

        #expect(second.id != first.id)
        #expect(app.path == [second.id])
        #expect(Set(app.scans.map(\.id)) == [first.id, second.id])
        #expect(app.scans.allSatisfy { $0.isFinished && $0.sent == nil })
    }

    @Test func closingANewScanWithoutPagesStaysOnTheReview() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let first = await fixture.capturedScan(in: app)
        app.startScan()
        app.closeCamera()

        #expect(app.path == [first.id])
        #expect(app.scans.map(\.id) == [first.id])
    }

    @Test func continueAddsPagesToTheSameScan() async throws {
        let fixture = try Fixture()
        let scan = await fixture.capturedScan(in: AppModel(processor: fixture.processor, settings: fixture.settings))

        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        app.continueScan(scan.id)
        let camera = try #require(app.camera)
        #expect(camera.id == scan.id)
        camera.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await camera.waitUntilIdle()
        app.finishCapture(camera)

        #expect(app.scans.count == 1)
        #expect(app.scans.first?.pages.count == 2)
        #expect(app.model(for: scan.id) === camera)
    }

    @Test func openingAFinishedScanOpensReview() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        app.path = []
        app.open(scan.id)

        #expect(app.path == [scan.id])
        #expect(app.camera == nil)
    }

    @Test func openingAScanInProgressOpensTheCameraOnIt() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = app.startScan()
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await scan.waitUntilIdle()
        app.closeCamera()
        app.open(scan.id)

        #expect(app.camera === scan)
        #expect(app.path.isEmpty)
    }

    @Test(arguments: [(SendMethod.share, "Shared"), (.paperless, "Archived")])
    func sendingReturnsHomeWithAConfirmation(method: SendMethod, toast: String) async throws {
        let fixture = try Fixture()
        let now = Date(timeIntervalSince1970: 1_794_700_000)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: { now })
        let scan = await fixture.capturedScan(in: app)

        app.didSend([scan], by: method)
        #expect(app.path.isEmpty)
        #expect(app.toast == toast)
        #expect(app.scans.first?.sent == Sent(date: now, method: method))
    }

    @Test func sendingSeveralScansMarksThemAllWithOneConfirmation() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let first = await fixture.capturedScan(in: app)
        let second = await fixture.capturedScan(in: app)

        app.didSend([first, second], by: .share)
        #expect(app.path.isEmpty)
        #expect(app.toast == "2 scans shared")
        #expect(app.scans.map(\.sent?.method) == [.share, .share])
    }

    @Test func listsTheFinishedScansNotSent() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let sent = await fixture.capturedScan(in: app)
        let waiting = await fixture.capturedScan(in: app)
        let inProgress = app.startScan()
        inProgress.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await inProgress.waitUntilIdle()
        app.closeCamera()
        app.didSend([sent], by: .share)

        #expect(app.notSent.map(\.id) == [waiting.id])
    }

    @Test func alwaysShowsShareForEveryOwner() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        #expect(app.sendMethods(for: [scan]) == [.share])
        #expect(app.namedSendMethod(for: [scan]) == nil)

        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let theirs = await fixture.capturedScan(in: app)
        theirs.setOwner(holding.id)
        #expect(app.sendMethods(for: [scan, theirs]) == [.share])
        #expect(app.sendMethods(for: []) == [.share], "Every owner when none is selected")
        #expect(app.sendingOwners(for: [theirs, scan, theirs]).map(\.id) == [holding.id, scan.owner.id])
        #expect(app.sendingOwners(for: []).count == 2)
    }

    @Test func tellsWhereAnOwnersDocumentsAreArchived() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        var owner = fixture.settings.value.defaultOwner
        #expect(app.summary(of: owner) == "Me, default, Paperless not connected")
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        #expect(!app.isConnected(owner), "Not connected without an archiver")
        #expect(app.archivesTo(owner) == nil)
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        #expect(app.summary(of: holding) == "Fernwood Holding, Paperless not connected")

        let tokens = MemoryTokens()
        let connected = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: Archiver(uploader: FakeUploader(), tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: FakeServer().fetch))
        #expect(!connected.isConnected(owner), "No token")
        #expect(connected.summary(of: owner) == "Me, default, Paperless not connected")
        try tokens.setToken("secret", for: owner.id)
        #expect(connected.isConnected(owner))
        #expect(connected.archivesTo(owner) == "paperless.example.com")
        #expect(connected.summary(of: owner) == "Me, default, archives to paperless.example.com")
    }

    @Test func suggestsSettingUpSendingUntilAnOwnerHasAServer() throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        #expect(app.suggestsSendSetup)
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        var owner = holding
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        fixture.settings.value.updateOwner(owner)
        #expect(!app.suggestsSendSetup)
        fixture.settings.value.updateOwner(holding)
        #expect(app.suggestsSendSetup)
        fixture.settings.value.dismissedSendSetup = true
        #expect(!app.suggestsSendSetup)
    }

    @Test func namesTheOwnersOfTheScansOnlyWhenThereAreSeveral() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let mine = await fixture.capturedScan(in: app)
        let other = await fixture.capturedScan(in: app)
        let third = await fixture.capturedScan(in: app)
        #expect(app.ownerLabel(of: [mine]) == nil)

        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        #expect(app.ownerLabel(of: []) == nil)
        #expect(app.ownerLabel(of: [mine]) == "Me")
        other.setOwner(holding.id)
        #expect(app.ownerLabel(of: [other, third]) == "2 owners")
        #expect(app.ownerLabel(of: [mine, other, third]) == "2 owners")
    }

    @Test func deletingAnOwnerMovesItsScansToAnother() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let employer = try #require(fixture.settings.addOwner("Halcyon Labs"))
        var format = employer
        format.fileNameFormat = FileNameFormat(separator: .underscore)
        fixture.settings.value.updateOwner(format)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        scan.rename("Office power")
        scan.setOwner(holding.id)
        #expect(app.scans(of: holding.id).map(\.id) == [scan.id])

        app.deleteOwner(holding.id, movingScansTo: holding.id)
        #expect(fixture.settings.value.hasOwner(holding.id))

        app.deleteOwner(holding.id, movingScansTo: employer.id)
        #expect(!fixture.settings.value.hasOwner(holding.id))
        #expect(app.scans.first?.owner?.id == employer.id)
        #expect(app.scans.first?.name == "Office_power")
    }

    @Test func deletingAnOwnerCanMoveItsScansToTheDefaultOwner() async throws {
        let fixture = try Fixture()
        let personal = fixture.settings.value.defaultOwnerID
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        scan.setOwner(holding.id)

        app.deleteOwner(holding.id, movingScansTo: personal)
        #expect(fixture.settings.value.owners.map(\.id) == [personal])
        #expect(app.scans.map(\.owner?.id) == [personal])
        #expect(scan.owner.id == personal)
    }

    @Test func deletingAnOwnerCanDeleteItsScans() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let mine = await fixture.capturedScan(in: app)
        let theirs = await fixture.capturedScan(in: app)
        theirs.setOwner(holding.id)

        app.deleteOwner(fixture.settings.value.defaultOwnerID, movingScansTo: nil)
        #expect(app.scans.count == 2)

        app.deleteOwner(holding.id, movingScansTo: nil)
        #expect(app.scans.map(\.id) == [mine.id])
        #expect(fixture.settings.value.owners.count == 1)
    }

    @Test func deletingAScanRemovesItEverywhere() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)

        app.delete(scan.id)
        #expect(app.scans.isEmpty)
        #expect(app.path.isEmpty)
        #expect(fixture.store.all().isEmpty)
    }

    @Test func deletesSeveralScansAtOnce() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let first = await fixture.capturedScan(in: app)
        let second = await fixture.capturedScan(in: app)
        let kept = await fixture.capturedScan(in: app)
        var elsewhere = Scan(name: "Elsewhere")
        elsewhere.pages = [ScanPage(quad: nil, analysis: .sample)]
        try fixture.store.save(elsewhere)
        app.path = [second.id]

        app.delete([first.id, second.id])
        #expect(app.scans.map(\.id) == [kept.id])
        #expect(app.path.isEmpty)
        #expect(Set(fixture.store.all().map(\.id)) == [kept.id, elsewhere.id])
        #expect(app.model(for: first.id) == nil)
    }

    @Test func openingAScanModelChangesNothingViewsObserve() throws {
        let fixture = try Fixture()
        var ids: [UUID] = []
        for name in ["Bill", "Letter"] {
            var scan = Scan(name: name)
            scan.pages = [ScanPage(quad: nil, analysis: .sample)]
            try fixture.store.save(scan)
            ids.append(scan.id)
        }
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let changes = Changes()
        withObservationTracking {
            _ = app.scans
            _ = app.model(for: ids[0])
        } onChange: {
            changes.count += 1
        }

        #expect(app.model(for: ids[1]) != nil)
        #expect(changes.count == 0)
    }

    @Test func deletesAScanNotOpenedSinceLaunch() throws {
        let fixture = try Fixture()
        var scan = Scan(name: "Bill")
        scan.pages = [ScanPage(quad: nil, analysis: .sample)]
        try fixture.store.save(scan)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)

        app.delete(scan.id)
        #expect(app.scans.isEmpty)
        #expect(fixture.store.all().isEmpty)
    }

    @Test func listsScansNewestFirstAndDropsTheOnesSentMoreThanADayAgo() throws {
        let fixture = try Fixture()
        let clock = TestClock()
        for (name, hours, method) in [("Archived", 25.0, SendMethod.paperless), ("Shared", 24.5, .share), ("Morning", 23.0, .paperless), ("Now", 0.0, .share)] {
            var scan = Scan(created: clock.now().addingTimeInterval(-(hours + 1) * 3600), name: name)
            scan.pages = [ScanPage(quad: nil, analysis: .sample)]
            scan.sent = Sent(date: clock.now().addingTimeInterval(-hours * 3600), method: method)
            try fixture.store.save(scan)
        }
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: clock.now)
        #expect(app.scans.map(\.name) == ["Now", "Morning"])

        clock.advance(days: 1)
        app.refresh()
        #expect(app.scans.isEmpty)
        #expect(fixture.store.all().isEmpty)
    }

    @Test func aSharedScanLeavesADayLater() async throws {
        let fixture = try Fixture()
        let clock = TestClock()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: clock.now)
        let scan = await fixture.capturedScan(in: app)
        app.didSend([scan], by: .share)
        clock.advance(hours: 23)
        app.refresh()
        #expect(app.scans.map(\.id) == [scan.id])

        clock.advance(hours: 2)
        app.refresh()
        #expect(app.scans.isEmpty)
    }

    @Test func neverDeletesAScanThatWasNotSent() throws {
        let fixture = try Fixture()
        let now = Date()
        var finished = Scan(created: now.addingTimeInterval(-400 * 86400), name: "Finished")
        finished.pages = [ScanPage(quad: nil, analysis: .sample)]
        finished.isFinished = true
        var inProgress = Scan(created: now.addingTimeInterval(-400 * 86400), name: "In progress")
        inProgress.pages = [ScanPage(quad: nil, analysis: .sample)]
        try fixture.store.save(finished)
        try fixture.store.save(inProgress)

        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: { now })
        #expect(Set(app.scans.map(\.name)) == ["Finished", "In progress"])
    }

    @Test func keepsAnExpiredScanWhileItIsOpen() throws {
        let fixture = try Fixture()
        let clock = TestClock()
        var reviewed = Scan(created: clock.now().addingTimeInterval(-3600), name: "Reviewed")
        var scanned = Scan(created: clock.now().addingTimeInterval(-7200), name: "Scanned")
        reviewed.pages = [ScanPage(quad: nil, analysis: .sample)]
        scanned.pages = [ScanPage(quad: nil, analysis: .sample)]
        reviewed.sent = Sent(date: clock.now(), method: .share)
        scanned.sent = Sent(date: clock.now(), method: .paperless)
        try fixture.store.save(reviewed)
        try fixture.store.save(scanned)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: clock.now)
        app.path = [reviewed.id]
        let review = try #require(app.model(for: reviewed.id))
        app.continueScan(scanned.id)

        clock.advance(days: 2)
        app.refresh()
        #expect(app.scans.map(\.id) == [reviewed.id, scanned.id])
        #expect(app.model(for: reviewed.id) === review)

        app.closeCamera()
        app.path = []
        app.refresh()
        review.rename("Water bill")
        #expect(app.scans.isEmpty)
        #expect(fixture.store.all().isEmpty)
        #expect(app.model(for: reviewed.id) == nil)
    }

    /// The folders of scans never saved used to stay when sent scans were kept forever.
    @Test func everyRefreshDeletesOnlyTheFoldersOfScansNeverSaved() throws {
        let fixture = try Fixture()
        var notSent = Scan(name: "Bill")
        notSent.pages = [ScanPage(quad: nil, analysis: .sample)]
        try fixture.store.save(notSent)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let capturing = app.startScan()
        let unsaved = try unreadableScanFolder(in: fixture.store)
        let olderFormat = try unreadableScanFolder(in: fixture.store, json: olderFormatJSON())
        let corrupt = try unreadableScanFolder(in: fixture.store, json: Data("{".utf8))
        let processing = try unreadableScanFolder(in: fixture.store, id: capturing.id)

        app.refresh()
        #expect(!exists(unsaved))
        #expect(exists(olderFormat))
        #expect(exists(corrupt))
        #expect(exists(processing))
        #expect(app.scans.map(\.id) == [notSent.id])
    }

    private func olderFormatJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(Scan(name: "Invoice"))) as? [String: Any])
        json["title"] = nil
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func unreadableScanFolder(in store: ScanStore, id: UUID = UUID(), json: Data? = nil) throws -> URL {
        let folder = store.directory(of: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try SyntheticPhoto.jpeg().write(to: store.photoURL(scanID: id, pageID: UUID()))
        if let json { try json.write(to: folder.appending(path: "scan.json")) }
        return folder
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

private final class Changes: @unchecked Sendable {
    var count = 0
}
