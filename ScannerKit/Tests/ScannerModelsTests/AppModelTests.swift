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

    @Test func deletingTheOnlyPageInTheCameraLeavesNoScan() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = app.startScan()
        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await scan.waitUntilIdle()
        scan.deletePage(scan.scan.pages[0].id)
        await scan.waitUntilIdle()
        app.closeCamera()

        #expect(app.scans.isEmpty)
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

    @Test func continueFromReviewReturnsToTheSameReview() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        app.camera = scan
        app.finishCapture(scan)
        #expect(app.path == [scan.id])
    }

    @Test func sendingReturnsHomeWithAConfirmation() async throws {
        let fixture = try Fixture()
        fixture.settings.value.email = "me@example.com"
        let now = Date(timeIntervalSince1970: 1_794_700_000)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: { now })
        let scan = await fixture.capturedScan(in: app)

        app.didSend(scan, by: .email)
        #expect(app.path.isEmpty)
        #expect(app.toast == "Emailed to me@example.com")
        #expect(app.scans.first?.sentBy == .email)
        #expect(app.scans.first?.sent == now)
    }

    @Test(arguments: [(SendMethod.email, "", "Emailed"), (.share, "me@example.com", "Shared")])
    func confirmsHowTheScanWasSent(method: SendMethod, email: String, toast: String) async throws {
        let fixture = try Fixture()
        fixture.settings.value.email = email
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        app.didSend(scan, by: method)
        #expect(app.toast == toast)
        #expect(app.scans.first?.sentBy == method)
    }

    @Test func savesToTheArchiveFolderAndConfirmsIt() async throws {
        let fixture = try Fixture()
        let folder = fixture.root.appending(path: "Paperwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try fixture.settings.chooseArchiveFolder(folder)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        await scan.buildPDF(delay: .zero)

        try app.saveToArchive(scan)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "\(scan.scan.name).pdf").path(percentEncoded: false)))
        #expect(app.toast == "Saved to Paperwork")
        #expect(app.scans.first?.sentBy == .files)
    }

    @Test func savesIntoTheFoldersOfACustomFormat() async throws {
        let fixture = try Fixture()
        let folder = fixture.root.appending(path: "Paperwork", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try fixture.settings.chooseArchiveFolder(folder)
        fixture.settings.value.fileNameFormat = FileNameFormat(isCustom: true, template: "{CATEGORY}/{ISSUER}")
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        scan.setDetails(DocumentDetails(category: .payslip, issuer: "Acme"))
        await scan.buildPDF(delay: .zero)

        try app.saveToArchive(scan)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Payslip/Acme.pdf").path(percentEncoded: false)))
        #expect(fixture.pdfExists("Acme"))
    }

    @Test func savingWithoutAnArchiveFolderFails() async throws {
        let fixture = try Fixture()
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let scan = await fixture.capturedScan(in: app)
        await scan.buildPDF(delay: .zero)

        #expect(throws: ArchiveFolder.SaveError.self) { try app.saveToArchive(scan) }
        #expect(scan.scan.sent == nil)
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
        #expect(fixture.store.byteCount() == 0)
    }

    @Test func listsScansNewestFirstAndDropsExpiredOnes() throws {
        let fixture = try Fixture()
        let now = Date()
        for (name, age) in [("Old", 8.0), ("Week", 6.0), ("Today", 0.0)] {
            var scan = Scan(created: now.addingTimeInterval(-age * 86400), name: name)
            scan.pages = [ScanPage(quad: nil, analysis: .sample)]
            try fixture.store.save(scan)
        }
        let app = AppModel(processor: fixture.processor, settings: fixture.settings, now: { now })
        #expect(app.scans.map(\.name) == ["Today", "Week"])

        fixture.settings.value.keepDays = 1
        app.refresh()
        #expect(app.scans.map(\.name) == ["Today"])
    }

    @Test func settingsSurviveARestart() throws {
        let fixture = try Fixture()
        fixture.settings.value.email = "me@example.com"
        fixture.settings.value.fileNameFormat.lowercase = true
        let reloaded = SettingsStore(defaults: fixture.defaults)
        #expect(reloaded.value.email == "me@example.com")
        #expect(reloaded.value.fileNameFormat.lowercase)
    }
}
