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

        let relaunched = AppModel(processor: ScanProcessor(store: fixture.store, context: CIContext(), paper: .a4), settings: fixture.settings)
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
        #expect(!fixture.pdfExists(built.scan.fileName))

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

    @Test func leavingTheForegroundSavesTheSettingsAtOnce() throws {
        let fixture = try Fixture()
        let settings = SettingsStore(defaults: fixture.defaults, saveDelay: .seconds(3600))
        let app = AppModel(processor: fixture.processor, settings: settings)
        settings.value.defaultOwner.email = "me@example.com"
        #expect(SettingsStore(defaults: fixture.defaults).value.defaultOwner.email != "me@example.com")

        app.setActive(false)
        #expect(SettingsStore(defaults: fixture.defaults).value.defaultOwner.email == "me@example.com")
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

    @Test(arguments: [(SendMethod.email, "me@example.com", "Emailed to me@example.com"), (.email, "", "Emailed"), (.share, "me@example.com", "Shared")])
    func sendingReturnsHomeWithAConfirmation(method: SendMethod, email: String, toast: String) async throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.email = email
        let now = Date(timeIntervalSince1970: 1_794_700_000)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: { now })
        let scan = await fixture.capturedScan(in: app)

        app.didSend([scan], by: method)
        #expect(app.path.isEmpty)
        #expect(app.toast == toast)
        #expect(app.scans.first?.sent == Sent(date: now, method: method))
    }

    @Test func savesToTheArchiveFolderAndConfirmsIt() async throws {
        let fixture = try Fixture()
        let folder = fixture.root.appending(path: "Paperwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try fixture.settings.chooseArchiveFolder(folder, for: nil)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        await scan.buildPDF(delay: .zero)

        try await app.saveToArchive([scan])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "\(scan.scan.name).pdf").path(percentEncoded: false)))
        #expect(app.toast == "Saved to Paperwork")
        #expect(app.scans.first?.sent?.method == .files)
    }

    @Test func savesToTheArchiveFolderWithoutBlockingTheMainActor() async throws {
        let fixture = try Fixture()
        let folder = fixture.root.appending(path: "Paperwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try fixture.settings.chooseArchiveFolder(folder, for: nil)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        await scan.preparePDF()
        let done = DispatchSemaphore(value: 0)
        await withCheckedContinuation { busy in
            Thread {
                NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: nil) { _ in
                    busy.resume()
                    _ = done.wait(timeout: .now() + 2)
                }
            }.start()
        }

        let saving = Task { try await app.saveToArchive([scan]) }
        let start = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(50))
        let waited = ContinuousClock.now - start
        done.signal()
        try await saving.value
        #expect(waited < .seconds(1))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "\(scan.scan.name).pdf").path(percentEncoded: false)))
    }

    @Test func savesIntoTheFoldersOfACustomFormat() async throws {
        let fixture = try Fixture()
        let folder = fixture.root.appending(path: "Paperwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try fixture.settings.chooseArchiveFolder(folder, for: nil)
        fixture.settings.value.defaultOwner.fileNameFormat = FileNameFormat(isCustom: true, template: "{CATEGORY}/{ISSUER}")
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        scan.setDetails(DocumentDetails(category: .payslip, issuer: "Acme"))
        await scan.buildPDF(delay: .zero)

        try await app.saveToArchive([scan])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Payslip/Acme.pdf").path(percentEncoded: false)))
        #expect(fixture.pdfExists("Acme"))
    }

    @Test func savingWithoutAnArchiveFolderFails() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        await scan.buildPDF(delay: .zero)

        await #expect(throws: AppModel.ArchiveError.self) { try await app.saveToArchive([scan]) }
        #expect(scan.scan.sent == nil)
    }

    @Test func sendingSeveralScansMarksThemAllWithOneConfirmation() async throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.email = "me@example.com"
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let first = await fixture.capturedScan(in: app)
        let second = await fixture.capturedScan(in: app)

        app.didSend([first, second], by: .email)
        #expect(app.path.isEmpty)
        #expect(app.toast == "2 scans emailed to me@example.com")
        #expect(app.scans.map(\.sent?.method) == [.email, .email])
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

    @Test func savesSeveralScansToTheArchiveFolder() async throws {
        let fixture = try Fixture()
        let folder = fixture.root.appending(path: "Paperwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try fixture.settings.chooseArchiveFolder(folder, for: nil)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let first = await fixture.capturedScan(in: app)
        let second = await fixture.capturedScan(in: app)
        second.rename("Water bill")
        await first.preparePDF()
        await second.preparePDF()

        try await app.saveToArchive([first, second])
        let saved = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
        #expect(saved == ["\(first.scan.name).pdf", "\(second.scan.name).pdf"].sorted())
        #expect(app.toast == "2 scans saved to Paperwork")
    }

    @Test func confirmsTheScansSavedBeforeOneFails() async throws {
        let fixture = try Fixture()
        let folder = fixture.root.appending(path: "Paperwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try fixture.settings.chooseArchiveFolder(folder, for: nil)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let ready = await fixture.capturedScan(in: app)
        let notReady = await fixture.capturedScan(in: app)
        await ready.preparePDF()

        let error = await #expect(throws: AppModel.ArchiveError.self) { try await app.saveToArchive([ready, notReady]) }
        #expect(error?.saved == [ready.id])
        #expect(ready.scan.sent?.method == .files)
        #expect(notReady.scan.sent == nil)
        #expect(app.toast == "Saved to Paperwork")
    }

    @Test func tellsWhenSavingToTheFolderFailedAsTheStorageIsFull() async throws {
        let fixture = try Fixture()
        let folder = fixture.root.appending(path: "Paperwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try fixture.settings.chooseArchiveFolder(folder, for: nil)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        await scan.preparePDF()

        app.saveToFolder = { _, _, _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        let full = await #expect(throws: AppModel.ArchiveError.self) { try await app.saveToArchive([scan]) }
        #expect(full?.isStorageFull == true)

        app.saveToFolder = { _, _, _, _ in throw ArchiveFolder.SaveError.unavailable }
        let unreachable = await #expect(throws: AppModel.ArchiveError.self) { try await app.saveToArchive([scan]) }
        #expect(unreachable?.isStorageFull == false)
        #expect(scan.scan.sent == nil)
    }

    @Test func savesEachScanToTheFolderOfItsOwner() async throws {
        let fixture = try Fixture()
        let personal = fixture.root.appending(path: "Personal", directoryHint: .isDirectory)
        let company = fixture.root.appending(path: "Fernwood", directoryHint: .isDirectory)
        for folder in [personal, company] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        try fixture.settings.chooseArchiveFolder(personal, for: nil)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let mine = await fixture.capturedScan(in: app)
        let theirs = await fixture.capturedScan(in: app)
        theirs.setOwner(holding.id)
        theirs.rename("Office power")
        await mine.preparePDF()
        await theirs.preparePDF()

        #expect(app.ownerWithoutFolder(among: [mine, theirs])?.id == holding.id)
        #expect(!app.hasFolder(for: [mine, theirs]))
        try fixture.settings.chooseArchiveFolder(company, for: holding.id)
        #expect(app.ownerWithoutFolder(among: [mine, theirs]) == nil)
        #expect(app.hasFolder(for: [mine, theirs]))
        #expect(!app.hasFolder(for: []))

        try await app.saveToArchive([mine, theirs])
        #expect(try FileManager.default.contentsOfDirectory(atPath: personal.path(percentEncoded: false)) == ["\(mine.scan.name).pdf"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: company.path(percentEncoded: false)) == ["Office power.pdf"])
        #expect(app.toast == "2 scans saved to Files")
    }

    @Test func showsSaveToFilesAndShareUnlessTurnedOffForAnOwnerOfTheScans() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        #expect(app.sendMethods(for: [scan]) == [.files, .share])
        fixture.settings.value.defaultOwner.email = "me@example.com"
        fixture.settings.value.defaultOwner.showsSaveToFiles = false
        #expect(app.sendMethods(for: [scan]) == [.email, .share])
        fixture.settings.value.defaultOwner.showsShare = false
        #expect(app.sendMethods(for: [scan]) == [.email])

        var holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let theirs = await fixture.capturedScan(in: app)
        theirs.setOwner(holding.id)
        #expect(app.sendMethods(for: [theirs]) == [.files, .share])
        #expect(app.sendMethods(for: [scan, theirs]) == [])
        #expect(app.sendMethods(for: []) == [], "Every owner when none is selected")
        holding.email = "accounts@example.com"
        holding.showsSaveToFiles = false
        fixture.settings.value.updateOwner(holding)
        #expect(app.sendMethods(for: [scan, theirs]) == [.email])
        #expect(app.sendingOwners(for: [theirs, scan, theirs]).map(\.id) == [holding.id, scan.owner.id])
        #expect(app.sendingOwners(for: []).count == 2)
    }

    @Test func tellsWhichWaysSendAnOwnersDocumentsInOneTap() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        var owner = fixture.settings.value.defaultOwner
        #expect(SendMethod.inBarOrder.filter { app.isSet($0, for: owner) } == [.share])
        #expect(app.summary(of: owner) == "Me, default, sends by Share")
        owner.showsShare = false
        owner.email = "me@example"
        #expect(app.summary(of: owner) == "Me, default, nothing set to send")
        owner.email = "me@example.com"
        owner.archiveFolder = try ArchiveFolder(url: fixture.root)
        #expect(app.summary(of: owner) == "Me, default, sends by Email, Save to Files")
        owner.showsSaveToFiles = false
        #expect(!app.isSet(.files, for: owner), "A folder without the button sends nothing")
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        #expect(!app.isSet(.paperless, for: owner), "Not connected without an archiver")
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        #expect(app.summary(of: holding) == "Fernwood Holding, sends by Share")

        let tokens = MemoryTokens()
        let connected = AppModel(processor: fixture.processor, settings: fixture.settings, archiver: Archiver(uploader: FakeUploader(), tokens: tokens, directory: fixture.root.appending(path: "Uploads"), fetch: FakeServer().fetch))
        #expect(!connected.isSet(.paperless, for: owner), "No token")
        try tokens.setToken("secret", for: owner.id)
        #expect(connected.summary(of: owner) == "Me, default, sends by Archive, Email")
    }

    @Test func suggestsSettingUpSendingUntilAnOwnerHasAnAddressOrServer() throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        #expect(app.suggestsSendSetup)
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        var owner = holding
        owner.paperless = PaperlessServer(url: URL(string: "https://paperless.example.com/")!)
        fixture.settings.value.updateOwner(owner)
        #expect(!app.suggestsSendSetup)
        fixture.settings.value.updateOwner(holding)
        fixture.settings.value.defaultOwner.email = "me@example"
        #expect(app.suggestsSendSetup, "An invalid address sends nothing")
        fixture.settings.value.dismissedSendSetup = true
        #expect(!app.suggestsSendSetup)
    }

    @Test func namesTheOwnersOfTheScansOnlyWhenThereAreSeveral() async throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.email = "me@example.com"
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
        #expect(app.byOwner([other, mine]).map(\.owner.id) == [holding.id, fixture.settings.value.defaultOwnerID])

        app.didSend([other], by: .email)
        #expect(app.toast == "Emailed")
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

    @Test func deletesAllScans() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let first = await fixture.capturedScan(in: app)
        _ = await fixture.capturedScan(in: app)
        await first.buildPDF(delay: .zero)
        app.deleteAllScans()
        #expect(app.scans.isEmpty)
        #expect(fixture.store.all().isEmpty)
        #expect(!fixture.pdfExists(first.scan.fileName))
        #expect(await fixture.store.byteCount() == 0)
    }

    @Test func listsScansNewestFirstAndDropsTheOnesSentLongerAgoThanTheRetention() throws {
        let fixture = try Fixture()
        let now = Date()
        for (name, age) in [("Old", 8.0), ("Week", 6.0), ("Today", 0.0)] {
            var scan = Scan(created: now.addingTimeInterval(-(age + 20) * 86400), name: name)
            scan.pages = [ScanPage(quad: nil, analysis: .sample)]
            scan.sent = Sent(date: now.addingTimeInterval(-age * 86400), method: .email)
            try fixture.store.save(scan)
        }
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: { now })
        #expect(app.scans.map(\.name) == ["Today", "Week"])

        fixture.settings.value.keepScans = .day
        app.refresh()
        #expect(app.scans.map(\.name) == ["Today"])
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
        fixture.settings.value.keepScans = .day

        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: { now })
        #expect(Set(app.scans.map(\.name)) == ["Finished", "In progress"])
    }

    @Test func keepsAnExpiredScanWhileItIsOpen() throws {
        let fixture = try Fixture()
        let now = Date()
        var reviewed = Scan(created: now.addingTimeInterval(-8 * 86400), name: "Reviewed")
        var scanned = Scan(created: now.addingTimeInterval(-9 * 86400), name: "Scanned")
        reviewed.pages = [ScanPage(quad: nil, analysis: .sample)]
        scanned.pages = [ScanPage(quad: nil, analysis: .sample)]
        reviewed.sent = Sent(date: now.addingTimeInterval(-8 * 86400), method: .share)
        scanned.sent = Sent(date: now.addingTimeInterval(-9 * 86400), method: .files)
        try fixture.store.save(reviewed)
        try fixture.store.save(scanned)
        fixture.settings.value.keepScans = .forever
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: { now })
        app.path = [reviewed.id]
        let review = try #require(app.model(for: reviewed.id))
        app.continueScan(scanned.id)

        fixture.settings.value.keepScans = .week
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

    @Test func retentionDeletesOnlyTheFoldersOfScansNeverSaved() throws {
        let fixture = try Fixture()
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
        #expect(app.scans.isEmpty)
    }

    @Test func deletingAllScansDeletesScanFoldersWithoutAReadableScan() async throws {
        let fixture = try Fixture()
        fixture.settings.value.keepScans = .forever
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let unsaved = try unreadableScanFolder(in: fixture.store)
        let olderFormat = try unreadableScanFolder(in: fixture.store, json: olderFormatJSON())
        app.refresh()
        #expect(exists(unsaved))

        app.deleteAllScans()
        #expect(!exists(unsaved))
        #expect(!exists(olderFormat))
        #expect(await fixture.store.byteCount() == 0)
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

    @Test func keepsScansForeverWhenAsked() throws {
        let fixture = try Fixture()
        let now = Date()
        var scan = Scan(created: now.addingTimeInterval(-400 * 86400), name: "Old")
        scan.pages = [ScanPage(quad: nil, analysis: .sample)]
        scan.sent = Sent(date: now.addingTimeInterval(-400 * 86400), method: .email)
        try fixture.store.save(scan)
        fixture.settings.value.keepScans = .forever
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: { now })
        #expect(app.scans.map(\.name) == ["Old"])
    }
}

private final class Changes: @unchecked Sendable {
    var count = 0
}
