import CoreImage
import Foundation
import PDFKit
@testable import ScannerKit
import Synchronization
import ScannerKitTesting
@testable import ScannerModels
import Testing

@MainActor
@Suite(.serialized)
struct ScanModelTests {
    @Test func addsPagesInCaptureOrderAndSavesThem() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.addPhoto(SyntheticPhoto.jpeg(page: .rect(x: 0.2, y: 0.1, width: 0.6, height: 0.6)), liveQuad: nil)
        #expect(model.processing == 2)
        await model.waitUntilIdle()

        #expect(model.processing == 0)
        #expect(model.scan.pages.count == 2)
        #expect(model.scan.pages[1].quad.map { $0.maxCornerDistance(to: .rect(x: 0.2, y: 0.1, width: 0.6, height: 0.6)) < 0.02 } == true)
        #expect(fixture.store.all().first?.pages == model.scan.pages)
    }

    @Test func saysWhenAPageCannotBeProcessed() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.addPhoto(Data("not a photo".utf8), liveQuad: nil)
        await model.waitUntilIdle()
        #expect(model.failure == "A page could not be processed.")
        #expect(model.processing == 0)
        #expect(model.scan.pages.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.directory(of: model.id).path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(1)))
    func makesAPageAgainWhenMakingItFailedWhileTheAppWasNotActive() async throws {
        let background = RecordingBackground()
        let fixture = try Fixture(background: background)
        let model = fixture.scanModel()
        let (started, release) = background.holdNext()
        model.addPhoto(Data("not a photo".utf8), liveQuad: nil)
        let pending = try #require(model.scan.pending.first)
        for await _ in started {}
        fixture.processor.gate.isPaused = true
        release()
        try await fixture.waitUntilGateHasWaiting(1)
        #expect(model.processing == 1)
        #expect(model.failure == nil)

        try SyntheticPhoto.jpeg().write(to: fixture.store.photoURL(scanID: model.id, pageID: pending.id))
        fixture.processor.gate.isPaused = false
        await model.waitUntilIdle()
        #expect(model.failure == nil)
        #expect(model.scan.pages.map(\.id) == [pending.id])
    }

    @Test(.timeLimit(.minutes(1)))
    func aPageMadeAgainOnceTheAppIsActiveKeepsItsPlace() async throws {
        let background = RecordingBackground()
        let fixture = try Fixture(background: background)
        let model = fixture.scanModel()
        let (started, release) = background.holdNext()
        model.addPhoto(Data("not a photo".utf8), liveQuad: nil)
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        let captured = model.scan.pending.map(\.id)
        for await _ in started {}
        fixture.processor.gate.isPaused = true
        release()
        try await fixture.waitUntilGateHasWaiting(1)

        try SyntheticPhoto.jpeg().write(to: fixture.store.photoURL(scanID: model.id, pageID: captured[0]))
        fixture.processor.gate.isPaused = false
        await model.waitUntilIdle()
        #expect(model.failure == nil)
        #expect(model.scan.pages.map(\.id) == captured)
    }

    @Test func emptyScansAreNeverSaved() throws {
        let fixture = try Fixture()
        _ = fixture.scanModel()
        #expect(fixture.store.all().isEmpty)
    }

    @Test func movesAPageToThePlaceOfAnother() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 3)
        let ids = model.scan.pages.map(\.id)

        model.movePage(ids[0], to: ids[2])
        #expect(model.scan.pages.map(\.id) == [ids[1], ids[2], ids[0]])
        model.movePage(ids[0], to: ids[1])
        #expect(model.scan.pages.map(\.id) == [ids[0], ids[1], ids[2]])
        model.movePage(ids[1], to: ids[1])
        #expect(model.scan.pages.map(\.id) == ids)
        #expect(fixture.store.all().first?.pages.map(\.id) == ids)
    }

    @Test func deletesAPageAndItsFiles() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 2)
        let page = model.scan.pages[0]
        model.deletePage(page.id)
        #expect(model.scan.pages.count == 1)
        await model.waitUntilIdle()
        #expect(!FileManager.default.fileExists(atPath: model.photoURL(of: page).path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(1)))
    func deletingAPageWhileItIsEditedLeavesNoFileBehind() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 2)
        let page = model.scan.pages[0]
        model.recrop(page.id, quad: nil)
        while !fixture.processor.gate.isBusy { try await Task.sleep(for: .milliseconds(1)) }
        model.deletePage(page.id)
        await model.waitUntilIdle()

        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.store.directory(of: model.id).path(percentEncoded: false))
        #expect(!files.contains { $0.hasPrefix(page.id.uuidString) })
        #expect(fixture.store.all().first?.pages == model.scan.pages)
    }

    @Test func deletingAPageSavesTheScanBeforeDeletingItsFiles() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 3)
        let photo = model.photoURL(of: model.scan.pages[0]).path(percentEncoded: false)
        var photoWhenSaved: Bool?
        model.didSave = { _ in photoWhenSaved = FileManager.default.fileExists(atPath: photo) }
        model.deletePage(model.scan.pages[0].id)
        #expect(photoWhenSaved == true)
        await model.waitUntilIdle()
        #expect(!FileManager.default.fileExists(atPath: photo))

        let kept = model.photoURL(of: model.scan.pages[0]).path(percentEncoded: false)
        let json = fixture.store.directory(of: model.id).appending(path: "scan.json")
        try FileManager.default.removeItem(at: json)
        try FileManager.default.createDirectory(at: json.appending(path: "blocked"), withIntermediateDirectories: true)
        model.deletePage(model.scan.pages[0].id)
        #expect(model.failure != nil)
        #expect(FileManager.default.fileExists(atPath: kept))
    }

    @Test func aScanKeepsItsLastPage() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        #expect(!model.canDeletePage)
        model.deletePage(model.scan.pages[0].id)
        await model.waitUntilIdle()

        #expect(model.scan.pages.count == 1)
        #expect(fixture.store.all().first?.pages == model.scan.pages)
    }

    @Test func theCameraCannotTakeTheLastPageOfAFinishedScan() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        #expect(model.canDeleteCapturedPage)
        model.finishCapture()
        #expect(!model.canDeleteCapturedPage)
        model.deleteCapturedPage(model.scan.pages[0].id)
        await model.waitUntilIdle()

        #expect(model.scan.pages.count == 1)
        #expect(fixture.store.all().first?.pages == model.scan.pages)
    }

    @Test func tellsWritesThatFailedForLackOfSpace() {
        #expect(CocoaError(.fileWriteOutOfSpace).isStorageFull)
        #expect(POSIXError(.ENOSPC).isStorageFull)
        #expect(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOSPC)]).isStorageFull)
        #expect(!CocoaError(.fileWriteNoPermission).isStorageFull)
        #expect(!POSIXError(.EACCES).isStorageFull)
    }

    @Test func saysWhenTheScanCouldNotBeSavedAsTheStorageIsFull() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.saveScan = { _ in throw CocoaError(.fileWriteOutOfSpace) }
        model.rename("Water bill")
        #expect(model.failure == "The scan could not be saved: the iPhone storage is full.")

        model.saveScan = { _ in throw CocoaError(.fileWriteNoPermission) }
        model.rename("Gas bill")
        #expect(model.failure == "The scan could not be saved.")
    }

    @Test func saysWhenThePDFCouldNotBeMadeAsTheStorageIsFull() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.makePDFData = { _ in throw POSIXError(.ENOSPC) }
        await model.buildPDF(delay: .zero)
        #expect(model.pdf == .storageFull)
        #expect(model.summary == "1 page · the iPhone storage is full")
    }

    @Test func deletingTheLastPageLeavesNothingBehind() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        await model.buildPDF(delay: .zero)
        #expect(fixture.pdfExists(model.scan.name))

        model.deleteCapturedPage(model.scan.pages[0].id)
        await model.waitUntilIdle()

        #expect(fixture.store.all().isEmpty)
        #expect(!fixture.pdfExists(model.scan.name))
        #expect(!FileManager.default.fileExists(atPath: fixture.store.directory(of: model.id).path(percentEncoded: false)))
    }

    @Test func deletingTheLastPageKeepsAPageStillProcessed() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        let deleted = model.scan.pages[0]
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.deleteCapturedPage(deleted.id)
        await model.waitUntilIdle()

        let page = try #require(model.scan.pages.first)
        #expect(fixture.store.all().first?.pages == [page])
        #expect(FileManager.default.fileExists(atPath: model.previewURL(of: page).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: model.previewURL(of: deleted).path(percentEncoded: false)))
    }

    @Test func quickEditsAreAllApplied() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        let id = model.scan.pages[0].id
        let orientation = model.scan.pages[0].analysis.orientation

        model.rotatePage(id)
        model.rotatePage(id)
        model.setLook(.color, of: [id])
        await model.waitUntilIdle()

        let page = model.scan.pages[0]
        #expect(page.analysis.orientation == orientation.turned.turned)
        #expect(page.cleanup.look == .color)
        #expect(page.revision == 3)
        #expect(model.updating == 0)
    }

    @Test func setsTheLookOfSeveralPages() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 3)
        model.setLook(.color, of: model.scan.pages.map(\.id))
        await model.waitUntilIdle()
        #expect(model.scan.pages.map(\.look) == [.color, .color, .color])
        #expect(model.scan.pages.map(\.revision) == [1, 1, 1])

        model.setLook(nil, of: [model.scan.pages[0].id])
        await model.waitUntilIdle()
        #expect(model.scan.pages[0].cleanup.look == nil)
        #expect(model.scan.pages[1].look == .color)
    }

    @Test func recropsAPage() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        let page = model.scan.pages[0]

        model.recrop(page.id, quad: nil)
        await model.waitUntilIdle()
        #expect(model.scan.pages[0].quad == nil)
        #expect(model.scan.pages[0].detectedQuad == page.quad)
        #expect(model.scan.pages[0].revision == page.revision + 1)
        #expect(fixture.store.all().first?.pages == model.scan.pages)
        #expect(FileManager.default.fileExists(atPath: fixture.store.flatURL(scanID: model.id, page: model.scan.pages[0]).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: fixture.store.flatURL(scanID: model.id, page: page).path(percentEncoded: false)))

        model.recrop(page.id, quad: page.detectedQuad)
        await model.waitUntilIdle()
        #expect(model.scan.pages[0].quad == page.quad)
    }

    @Test func deletingBeforePagesAreProcessedLeavesNothingBehind() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.delete()
        await model.waitUntilIdle()

        #expect(fixture.store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.directory(of: model.id).path(percentEncoded: false)))
    }

    @Test func deletingWhileAPageIsProcessedLeavesNothingBehind() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        let directory = fixture.store.directory(of: model.id).path(percentEncoded: false)
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        while !FileManager.default.fileExists(atPath: directory) { try await Task.sleep(for: .milliseconds(1)) }
        model.delete()
        await model.waitUntilIdle()

        #expect(fixture.store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.directory(of: model.id).path(percentEncoded: false)))
    }

    @Test func renameUsesTheFileNameFormatAndMovesThePDF() async throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.fileNameFormat = FileNameFormat(datePosition: .start, separator: .dash, lowercase: true)
        let model = await fixture.scanModel(pages: 1)
        await model.buildPDF(delay: .zero)
        let first = model.scan.name
        #expect(fixture.pdfExists(first))

        model.rename("Lumen Energy invoice")
        #expect(model.scan.title == "Lumen Energy invoice")
        #expect(model.scan.isNamedByUser)
        #expect(model.scan.name == "\(FileNamer.isoDate(model.scan.details.date ?? model.scan.created))-lumen-energy-invoice")
        #expect(fixture.pdfExists(model.scan.name))
        #expect(!fixture.pdfExists(first))
    }

    @Test func anEmptyNameFallsBackToTheFirstSuggestion() throws {
        let fixture = try Fixture()
        var scan = Scan(name: "Scan", title: "Scan")
        scan.suggestions = ["Invoice Lumen Energy", "Invoice 1234"]
        let model = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)
        model.rename("   ")
        #expect(model.scan.title == "Invoice Lumen Energy")
    }

    @Test func anEmptyNameWithoutSuggestionsFallsBackToTheDate() throws {
        let fixture = try Fixture()
        let created = Date.day("2026-11-12")
        let model = ScanModel(scan: Scan(created: created, name: "Scan"), processor: fixture.processor, settings: fixture.settings)
        model.rename("   ")
        #expect(model.scan.title == "Scan 2026-11-12")
    }

    @Test(arguments: ["  Lumen   bill ", "", "   "])
    func previewsTheFileNameATypedNameGets(typed: String) throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.fileNameFormat = FileNameFormat(separator: .dash)
        let model = fixture.scanModel()
        let preview = model.fileNameSegments(for: model.finalName(typed)).map(\.text).joined()
        model.rename(typed)
        #expect(preview == model.scan.name)
    }

    @Test func twoScansWithTheSameNameGetDifferentFiles() async throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.fileNameFormat = FileNameFormat(separator: .dash)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let first = await fixture.capturedScan(in: app)
        let second = await fixture.capturedScan(in: app)
        first.rename("Invoice")
        second.rename("Invoice")
        #expect(first.scan.name == "Invoice")
        #expect(second.scan.name == "Invoice-2")
    }

    @Test func aRenameIsNotReplacedBySuggestions() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.rename("Mine")
        await model.waitUntilIdle()
        #expect(model.scan.title == "Mine")
    }

    @Test func reusesACorrectedNameForTheNextDocumentFromTheSameIssuer() async throws {
        let fixture = try Fixture()
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "LUMEN ENERGY SAS").render(), quality: 0.9))
        let first = fixture.scanModel()
        first.addPhoto(photo, liveQuad: nil)
        await first.waitUntilIdle()
        let suggestion = try #require(first.scan.suggestions.first)
        #expect(suggestion != first.fallbackTitle)
        first.rename("Lumen Energy bill")

        let second = fixture.scanModel()
        second.addPhoto(photo, liveQuad: nil)
        await second.waitUntilIdle()
        #expect(second.scan.title == "Lumen Energy bill")
        #expect(second.scan.suggestions.first == suggestion)
        #expect(!second.scan.isNamedByUser)

        second.rename(suggestion)
        let third = fixture.scanModel()
        third.addPhoto(photo, liveQuad: nil)
        await third.waitUntilIdle()
        #expect(third.scan.title == suggestion)
    }

    @Test func changingTheFormatRenamesTheFile() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.rename("Lumen invoice")
        fixture.settings.value.defaultOwner.fileNameFormat = FileNameFormat(separator: .underscore, lowercase: true)
        model.applyFileName()
        #expect(model.scan.name == "lumen_invoice")
        #expect(model.scan.title == "Lumen invoice")
    }

    @Test func buildsThePDFWithItsSize() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 2)
        await model.buildPDF(delay: .zero)
        guard case .ready(let url, let size) = model.pdf else {
            Issue.record("PDF not ready: \(model.pdf)")
            return
        }
        #expect(url == fixture.store.pdfURL(of: model.scan))
        #expect(size > 1000)
    }

    @Test func preparesThePDFOnlyWhenItIsNotCurrent() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        await model.preparePDF()
        guard case .ready(let url, let size) = model.pdf else {
            Issue.record("PDF not ready: \(model.pdf)")
            return
        }
        #expect(model.hasCurrentPDF)
        try Data("%PDF".utf8).write(to: url)
        await model.preparePDF()
        #expect(try Data(contentsOf: url) == Data("%PDF".utf8))

        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        #expect(!model.hasCurrentPDF)
        await model.preparePDF()
        guard case .ready(_, let grown) = model.pdf else {
            Issue.record("PDF not ready: \(model.pdf)")
            return
        }
        #expect(grown > size)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func rebuildsAPDFRenamedOrDeletedInFiles() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        await model.preparePDF()
        guard case .ready(let url, _) = model.pdf else {
            Issue.record("PDF not ready: \(model.pdf)")
            return
        }

        try FileManager.default.moveItem(at: url, to: fixture.store.documentsDirectory.appending(path: "Mine.pdf"))
        await model.preparePDF()
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        try FileManager.default.removeItem(at: url)
        await model.preparePDF()
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(model.hasCurrentPDF)
    }

    @Test func aRenameMakesThePDFNotCurrent() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        await model.preparePDF()
        #expect(model.hasCurrentPDF)

        model.rename("Water bill")
        #expect(!model.hasCurrentPDF)
        await model.preparePDF()
        #expect(model.hasCurrentPDF)
        guard case .ready(let url, _) = model.pdf else {
            Issue.record("PDF not ready: \(model.pdf)")
            return
        }
        #expect(url == fixture.store.pdfURL(of: model.scan))
    }

    @Test func aCommentIsWrittenInThePDF() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        await model.preparePDF()

        model.setComment("  Lunch with Ada and Linus\n")
        #expect(model.scan.comment == "Lunch with Ada and Linus")
        #expect(!model.hasCurrentPDF)
        await model.preparePDF()
        guard case .ready(let url, _) = model.pdf else {
            Issue.record("PDF not ready: \(model.pdf)")
            return
        }
        #expect(PDFDocument(url: url)?.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String == "Lunch with Ada and Linus")
        #expect(fixture.store.all().first?.comment == "Lunch with Ada and Linus")
    }

    @Test func aBlankCommentRemovesIt() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.setComment("Lunch with Ada")
        model.setComment(" \n ")
        #expect(model.scan.comment == nil)
    }

    @Test func doesNotRebuildACurrentPDF() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        await model.buildPDF(delay: .zero)
        guard case .ready(let url, _) = model.pdf else {
            Issue.record("PDF not ready: \(model.pdf)")
            return
        }
        try Data("%PDF".utf8).write(to: url)
        await model.buildPDF(delay: .zero)
        #expect(try Data(contentsOf: url) == Data("%PDF".utf8))
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingTheCallerStopsTheBuild() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        let builds = PDFBuilds()
        model.makePDFData = { _ in
            builds.start()
            try await Task.sleep(for: .seconds(120))
            return Data("%PDF".utf8)
        }
        let caller = Task { await model.buildPDF(delay: .zero) }
        await builds.waitForStart()
        caller.cancel()
        await caller.value
        #expect(model.pdf != .failed)
        #expect(!fixture.pdfExists(model.scan.name))
    }

    @Test func keepsABuildThatFinishedAfterItsCallerWasCancelled() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        let builds = PDFBuilds()
        model.makePDFData = { _ in
            builds.start()
            await builds.waitForRelease()
            return Data("%PDF".utf8)
        }
        let caller = Task { await model.buildPDF(delay: .zero) }
        await builds.waitForStart()
        caller.cancel()
        builds.release()
        await caller.value
        #expect(model.hasCurrentPDF)
        #expect(fixture.pdfExists(model.scan.name))
    }

    @Test func neverRunsTwoBuildsOfAScanAtOnce() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        let builds = PDFBuilds()
        model.makePDFData = { scan in
            builds.start()
            try await Task.sleep(for: .milliseconds(100))
            builds.finish()
            return Data("%PDF \(scan.title)".utf8)
        }
        async let first: Void = model.buildPDF(delay: .zero)
        async let second: Void = model.buildPDF(delay: .zero)
        _ = await (first, second)
        #expect(builds.count == 1)

        model.rename("Gas bill")
        let gas = model.scan.name
        let stale = Task { await model.buildPDF(delay: .zero) }
        await builds.waitForStart(of: 2)
        model.rename("Water bill")
        await model.buildPDF(delay: .zero)
        await stale.value
        #expect(builds.count == 3)
        #expect(builds.mostAtOnce == 1)
        #expect(model.hasCurrentPDF)
        #expect(try Data(contentsOf: fixture.store.pdfURL(of: model.scan)) == Data("%PDF Water bill".utf8))
        #expect(!fixture.pdfExists(gas))
    }

    @Test(.timeLimit(.minutes(1)))
    func buildsThePDFOnlyOnceThePagesAreMade() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        let builds = PDFBuilds()
        model.makePDFData = { scan in
            builds.start()
            builds.finish()
            return Data("%PDF \(scan.pages.count)".utf8)
        }
        let release = await fixture.holdGate()
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        let stale = Task { await model.buildPDF(delay: .zero) }
        let build = Task { await model.buildPDF(delay: .zero) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(builds.count == 0)

        stale.cancel()
        await release()
        await build.value
        await stale.value
        #expect(builds.count == 1)
        #expect(model.hasCurrentPDF)
        #expect(try Data(contentsOf: fixture.store.pdfURL(of: model.scan)) == Data("%PDF 3".utf8))
    }

    @Test(.timeLimit(.minutes(1)))
    func pageWorkOfEveryScanWaitsForItsTurn() async throws {
        let fixture = try Fixture()
        let edited = await fixture.scanModel(pages: 1)
        let page = edited.scan.pages[0]
        let built = await fixture.scanModel(pages: 1)
        let captured = fixture.scanModel()
        let release = await fixture.holdGate()

        captured.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        edited.rotatePage(page.id)
        let build = Task { await built.buildPDF(delay: .zero) }
        try await fixture.waitUntilGateHasWaiting(3)
        #expect(captured.scan.pages.isEmpty)
        #expect(edited.scan.pages[0].revision == page.revision)
        #expect(!fixture.pdfExists(built.scan.name))

        await release()
        await captured.waitUntilIdle()
        await edited.waitUntilIdle()
        await build.value
        #expect(captured.scan.pages.count == 1)
        #expect(edited.scan.pages[0].revision == page.revision + 1)
        #expect(built.hasCurrentPDF)
    }

    @Test func keepsTheAppRunningWhilePagesAndThePDFAreWritten() async throws {
        let background = RecordingBackground()
        let fixture = try Fixture(background: background)
        let model = fixture.scanModel()
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        var savedWhileRunning: [Bool] = []
        model.didSave = { _ in savedWhileRunning.append(background.running == 1) }
        await model.waitUntilIdle()
        #expect(!savedWhileRunning.isEmpty)
        #expect(!savedWhileRunning.contains(false))

        let begun = background.begun
        await model.buildPDF(delay: .zero)
        #expect(model.hasCurrentPDF)
        #expect(background.begun == begun + 2)
        #expect(background.running == 0)
    }

    @Test(arguments: [true, false])
    func aPDFWrittenWhileTheScanIsRenamedOrDeletedIsNotLeftBehind(renamed: Bool) async throws {
        let background = RecordingBackground()
        let fixture = try Fixture(background: background)
        let model = await fixture.scanModel(pages: 1)
        let name = model.scan.name
        model.makePDFData = { _ in Data("%PDF".utf8) }
        let (started, release) = background.holdNext()
        let build = Task { await model.buildPDF(delay: .zero) }
        for await _ in started {}
        if renamed { model.rename("Water bill") } else { model.delete() }
        release()
        await build.value
        #expect(!fixture.pdfExists(name))

        guard renamed else { return }
        await model.buildPDF(delay: .zero)
        #expect(fixture.pdfExists("Water bill"))
        #expect(!fixture.pdfExists(name))
    }

    @Test func editedDetailsRenameTheFileWithACustomFormat() async throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.fileNameFormat = FileNameFormat(isCustom: true, template: "{CATEGORY} {YYYY} {ISSUER} {NUMBER}")
        let model = await fixture.scanModel(pages: 1)
        let year = String(FileNamer.isoDate(model.scan.created).prefix(4))
        await model.buildPDF(delay: .zero)
        model.setDetails(DocumentDetails(category: .insurance, issuer: "Acme Mutual", number: "P-1234"))
        #expect(model.scan.areDetailsEditedByUser)
        #expect(model.scan.name == "Insurance \(year) Acme Mutual P-1234")
        #expect(fixture.pdfExists("Insurance \(year) Acme Mutual P-1234"))
        #expect(fixture.store.all().first?.details.issuer == "Acme Mutual")
    }

    @Test func aSuggestedNameLeavesOutTheDetailsTheFormatShows() throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.fileNameFormat = FileNameFormat(isCustom: true, template: "{CATEGORY} {ISSUER} {NAME}")
        var scan = Scan(name: "Scan", title: "Facture Lumen Energy")
        scan.suggestions = ["Facture Lumen Energy"]
        scan.suggestedParts = SuggestedParts(type: "Facture", issuer: "Lumen Energy")
        scan.details = DocumentDetails(category: .invoice, issuer: "Lumen Energy")
        let model = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)
        #expect(model.fileName(for: "Facture Lumen Energy") == "Invoice Lumen Energy")
        #expect(model.fileName(for: "December") == "Invoice Lumen Energy December")
        model.rename("Facture Lumen Energy")
        #expect(model.scan.name == "Invoice Lumen Energy")
    }

    private func suggestedScan(title: String, parts: SuggestedParts, issuer: String?, namedByUser: Bool = false) -> Scan {
        var scan = Scan(name: "Scan", title: title)
        scan.suggestions = [title]
        scan.suggestedParts = parts
        scan.details = DocumentDetails(category: .invoice, issuer: issuer)
        scan.isNamedByUser = namedByUser
        return scan
    }

    @Test func aSuggestedNameFollowsTheCorrectedIssuer() throws {
        let fixture = try Fixture()
        let scan = suggestedScan(title: "Facture Lumen Energy", parts: SuggestedParts(type: "Facture", issuer: "Lumen Energy"), issuer: "Lumen Energy")
        let model = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)
        model.setDetails(DocumentDetails(category: .invoice, issuer: "Northwind Power"))
        #expect(model.scan.title == "Facture Northwind Power")
        #expect(model.scan.suggestions == ["Facture Northwind Power"])
        #expect(model.scan.name == "Facture Northwind Power")
        #expect(!model.scan.isNamedByUser)
    }

    @Test func aTypedNameStaysWhenTheIssuerIsCorrected() throws {
        let fixture = try Fixture()
        let scan = suggestedScan(title: "Electricity", parts: SuggestedParts(type: "Facture", issuer: "Lumen Energy"), issuer: "Lumen Energy", namedByUser: true)
        let model = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)
        model.setDetails(DocumentDetails(category: .invoice, issuer: "Northwind Power"))
        #expect(model.scan.title == "Electricity")
        #expect(model.scan.suggestions == ["Facture Northwind Power"])
    }

    @Test func aHeadingNameDoesNotTakeTheCorrectedIssuer() throws {
        let fixture = try Fixture()
        let scan = suggestedScan(title: "Avis de passage", parts: SuggestedParts(type: "Avis de passage"), issuer: "Lumen Energy")
        let model = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)
        model.setDetails(DocumentDetails(category: .invoice, issuer: "Northwind Power"))
        #expect(model.scan.title == "Avis de passage")
    }

    @Test func marksTheValuesThatComeFromCorrections() async throws {
        let fixture = try Fixture()
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "LUMEN ENERGY SAS").render(), quality: 0.9))
        let first = fixture.scanModel()
        first.addPhoto(photo, liveQuad: nil)
        await first.waitUntilIdle()
        #expect(first.scan.remembered.isEmpty)
        let read = try #require(first.scan.read)
        first.setDetails(DocumentDetails(category: .medical, issuer: "Quick Garage", date: first.scan.details.date))
        first.rename("Garage bill")

        let second = fixture.scanModel()
        second.addPhoto(photo, liveQuad: nil)
        await second.waitUntilIdle()
        #expect(second.scan.remembered == [.name, .category, .issuer])
        #expect(second.scan.read == read)
        #expect(fixture.settings.learnedIssuer(for: second.scan.issuerKeys)?.label == "Quick Garage")

        second.setDetails(DocumentDetails(category: .invoice, issuer: "Quick Garage", date: second.scan.details.date))
        second.rename("Repair")
        #expect(second.scan.remembered == [.issuer])
    }

    private func rememberedScan() -> Scan {
        var scan = Scan(name: "Scan", title: "Garage bill")
        scan.read = ReadDocument(details: DocumentDetails(category: .invoice, issuer: "Lumen Energy"), parts: SuggestedParts(type: "Facture", issuer: "Lumen Energy"))
        scan.details = DocumentDetails(category: .medical, issuer: "Quick Garage")
        scan.suggestedParts = SuggestedParts(type: "Facture", issuer: "Quick Garage")
        scan.suggestions = ["Facture Quick Garage"]
        scan.issuerKeys = ["lumen"]
        scan.remembered = [.name, .category, .issuer]
        return scan
    }

    @Test func forgettingPutsBackWhatWasRead() throws {
        let fixture = try Fixture()
        fixture.settings.learn(keys: ["lumen"]) { $0.issuer = "Quick Garage"; $0.category = .medical; $0.name = NamePattern(name: "Garage bill", details: .init(), date: .now) }
        let model = ScanModel(scan: rememberedScan(), processor: fixture.processor, settings: fixture.settings)

        model.forget([.issuer, .category])
        #expect(model.scan.details.issuer == "Lumen Energy")
        #expect(model.scan.details.category == .invoice)
        #expect(model.scan.suggestions == ["Facture Lumen Energy"])
        #expect(model.scan.title == "Garage bill")
        #expect(model.scan.remembered == [.name])
        #expect(fixture.settings.learnedIssuer(for: ["lumen"])?.issuer == nil)
        #expect(fixture.settings.learnedIssuer(for: ["lumen"])?.name != nil)

        model.forget([.name])
        #expect(model.scan.title == "Facture Lumen Energy")
        #expect(model.scan.name == "Facture Lumen Energy")
        #expect(model.scan.remembered.isEmpty)
        #expect(fixture.settings.learnedIssuer(for: ["lumen"]) == nil)
    }

    @Test func reusesTheIssuerAndCategoryCorrectedForTheSameIssuer() async throws {
        let fixture = try Fixture()
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "LUMEN ENERGY SAS").render(), quality: 0.9))
        let first = fixture.scanModel()
        first.addPhoto(photo, liveQuad: nil)
        await first.waitUntilIdle()
        try #require(!first.scan.issuerKeys.isEmpty)
        let car = try #require(fixture.settings.addCategory("Car"))
        first.setDetails(DocumentDetails(category: car, issuer: "Quick Garage", date: first.scan.details.date))

        let second = fixture.scanModel()
        second.addPhoto(photo, liveQuad: nil)
        await second.waitUntilIdle()
        #expect(second.scan.details.category == car)
        #expect(second.scan.details.issuer == "Quick Garage")
        #expect(!second.scan.areDetailsEditedByUser)
    }

    @Test func learnsANameOnlyWhenItDiffersAndTheIssuerCanBeRecognized() throws {
        let fixture = try Fixture()
        var scan = Scan(name: "Scan", title: "Invoice Lumen")
        scan.suggestions = ["Invoice Lumen", "Invoice 1234"]
        scan.issuerKeys = ["lumen"]
        let model = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)
        #expect(model.learnedPattern(for: "Lumen electricity") != nil)
        #expect(model.learnedPattern(for: "Invoice Lumen") == nil)
        #expect(fixture.scanModel().learnedPattern(for: "Mine") == nil)
    }

    @Test func reusesACorrectedNameAfterTheIssuerWasCorrectedToo() async throws {
        let fixture = try Fixture()
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "LUMEN ENERGY SAS").render(), quality: 0.9))
        let first = fixture.scanModel()
        first.addPhoto(photo, liveQuad: nil)
        await first.waitUntilIdle()
        var details = first.scan.details
        details.issuer = "Lumen"
        first.setDetails(details)
        first.rename("Lumen bill")

        let second = fixture.scanModel()
        second.addPhoto(photo, liveQuad: nil)
        await second.waitUntilIdle()
        #expect(second.scan.details.issuer == "Lumen")
        #expect(second.scan.title == "Lumen bill")
    }

    @Test func anotherOwnerNamesTheFileWithItsFormatAndIsReusedForTheIssuer() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        var owner = holding
        owner.fileNameFormat = FileNameFormat(separator: .underscore)
        fixture.settings.value.updateOwner(owner)
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "LUMEN ENERGY SAS").render(), quality: 0.9))
        let first = fixture.scanModel()
        first.addPhoto(photo, liveQuad: nil)
        await first.waitUntilIdle()
        #expect(first.hasDefaultOwner)
        first.rename("Office power")

        first.setOwner(holding.id)
        #expect(first.owner.id == holding.id)
        #expect(!first.hasDefaultOwner)
        #expect(first.scan.name == "Office_power")
        #expect(fixture.pdfExists("Office_power") == fixture.pdfExists(first.scan.name))

        let second = fixture.scanModel()
        second.addPhoto(photo, liveQuad: nil)
        await second.waitUntilIdle()
        #expect(second.owner.id == holding.id)
        #expect(second.scan.remembered.contains(.owner))

        second.forget([.owner])
        #expect(second.hasDefaultOwner)
        #expect(!second.scan.remembered.contains(.owner))
        #expect(fixture.settings.learnedIssuer(for: second.scan.issuerKeys)?.owner == nil)
    }

    @Test func readingThePageAgainKeepsSayingTheOwnerIsRemembered() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "LUMEN ENERGY SAS").render(), quality: 0.9))
        let first = fixture.scanModel()
        first.addPhoto(photo, liveQuad: nil)
        await first.waitUntilIdle()
        first.setOwner(holding.id)

        let second = fixture.scanModel()
        second.addPhoto(photo, liveQuad: nil)
        await second.waitUntilIdle()
        #expect(second.scan.remembered == [.owner])
        second.deleteCapturedPage(try #require(second.scan.pages.first?.id))
        second.addPhoto(photo, liveQuad: nil)
        await second.waitUntilIdle()
        #expect(second.owner.id == holding.id)
        #expect(second.scan.remembered == [.owner])
    }

    @Test func changingTheDefaultOwnerMovesNoScan() throws {
        let fixture = try Fixture()
        let personal = fixture.settings.value.defaultOwnerID
        var holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        holding.fileNameFormat = FileNameFormat(separator: .underscore)
        fixture.settings.value.updateOwner(holding)
        let model = fixture.scanModel(title: "Office power")

        fixture.settings.value.defaultOwnerID = holding.id
        #expect(model.owner.id == personal)
        #expect(model.hasDefaultOwner)
        #expect(model.ownerCaption == nil)
        let rent = fixture.scanModel(title: "Office rent")
        #expect(rent.owner.id == holding.id)
        #expect(rent.ownerCaption == "Default")
    }

    @Test func aRememberedOwnerIsNotUsedWithASingleOwner() async throws {
        let fixture = try Fixture()
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "LUMEN ENERGY SAS").render(), quality: 0.9))
        let first = fixture.scanModel()
        first.addPhoto(photo, liveQuad: nil)
        await first.waitUntilIdle()
        fixture.settings.learn(keys: first.scan.issuerKeys) { $0.owner = fixture.settings.value.defaultOwnerID }

        let second = fixture.scanModel()
        second.addPhoto(photo, liveQuad: nil)
        await second.waitUntilIdle()
        #expect(second.hasDefaultOwner)
        #expect(second.scan.remembered.isEmpty)
    }

    /// A scan whose first page reads as these lines from the top, instead of what is on its photo.
    private func scan(reading texts: [String], in fixture: Fixture) async -> ScanModel {
        let model = fixture.scanModel()
        let lines = textLines(texts)
        model.readDocument = { _, _, owners in DocumentDetector().detect(lines: lines, owners: owners) }
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await model.waitUntilIdle()
        return model
    }

    /// These lines from the top of a page.
    private func textLines(_ texts: [String]) -> [TextLine] {
        texts.enumerated().map { TextLine(text: $1, frame: CGRect(x: 0.08, y: 0.04 + Double($0) * 0.03, width: 0.4, height: 0.012)) }
    }

    /// Makes the page read as these lines only once the returned closure is called, after `started` tells that the reading began.
    private func holdReading(of model: ScanModel, reading texts: [String]) -> (started: AsyncStream<Void>, release: () -> Void) {
        let lines = textLines(texts)
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        model.readDocument = { _, _, owners in
            didStart.yield()
            for await _ in released {}
            return DocumentDetector().detect(lines: lines, owners: owners)
        }
        return (started, { release.finish() })
    }

    @Test func anOwnerNamedOnThePageWinsOverTheOneRememberedForTheIssuer() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let employer = try #require(fixture.settings.addOwner("Halcyon Labs"))
        let first = await scan(reading: ["LUMEN ENERGY SAS", "Invoice"], in: fixture)
        first.setOwner(employer.id)

        let second = await scan(reading: ["LUMEN ENERGY SAS", "Invoice", "FERNWOOD SAS"], in: fixture)
        #expect(fixture.settings.learnedIssuer(for: second.scan.issuerKeys)?.owner == employer.id)
        #expect(second.scan.details.issuer == "Lumen Energy")
        #expect(second.owner.id == holding.id)
        #expect(!second.hasDefaultOwner)
        #expect(second.scan.remembered.isEmpty)
        #expect(second.ownerCaption == "Its name is on the page")
        #expect(fixture.store.all().first { $0.id == second.id }?.owner == ScanOwner(id: holding.id, clue: .name))
    }

    @Test func anOwnerWhoseAddressIsOnThePageGetsIt() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        fixture.settings.setAddress("12 quai Perrache\n69002 Lyon", of: holding.id)
        let model = await scan(reading: ["LUMEN ENERGY SAS", "Invoice", "12 quai Perrache", "69002 Lyon"], in: fixture)
        #expect(model.owner.id == holding.id)
        #expect(model.ownerCaption == "Its address is on the page")
    }

    @Test func aNameTellsTheDefaultOwnerToo() async throws {
        let fixture = try Fixture()
        let me = fixture.settings.value.defaultOwnerID
        #expect(fixture.settings.renameOwner(me, to: "Camille Rouvière"))
        let model = await scan(reading: ["LUMEN ENERGY SAS", "Invoice", "Mme Camille Rouvière"], in: fixture)
        #expect(model.owner.id == me)
        #expect(!model.hasDefaultOwner)
        #expect(model.ownerCaption == "Its name is on the page")
        #expect(model.scan.details.issuer == "Lumen Energy")
    }

    @Test func thePlaceholderNameTellsNothing() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        fixture.settings.value.defaultOwnerID = holding.id
        let model = await scan(reading: ["Me", "Invoice"], in: fixture)
        #expect(model.owner.id == holding.id)
        #expect(model.hasDefaultOwner)
        #expect(model.ownerCaption == "Default")
    }

    @Test func aChosenOwnerStaysWhateverIsOnThePage() async throws {
        let fixture = try Fixture()
        try #require(fixture.settings.addOwner("Fernwood Holding") != nil)
        let employer = try #require(fixture.settings.addOwner("Halcyon Labs"))
        let model = fixture.scanModel()
        model.setOwner(employer.id)
        model.readDocument = { _, _, owners in
            DocumentDetector().detect(lines: [TextLine(text: "Fernwood Holding", frame: CGRect(x: 0.08, y: 0.1, width: 0.4, height: 0.012))], owners: owners)
        }
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await model.waitUntilIdle()
        #expect(model.owner.id == employer.id)
        #expect(model.ownerCaption == nil)
    }

    @Test func givingTheScanToAnotherOwnerForgetsWhatTheTextTold() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let model = await scan(reading: ["LUMEN ENERGY SAS", "Invoice", "Fernwood Holding"], in: fixture)
        #expect(model.owner.id == holding.id)
        model.setOwner(fixture.settings.value.defaultOwnerID)
        #expect(model.scan.owner?.clue == nil)
        #expect(model.ownerCaption == nil)
    }

    @Test func trimsTypedDetailsAndRemovesBlankOnes() throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.setDetail(\.issuer, to: "  Lumen Energy ")
        #expect(model.scan.details.issuer == "Lumen Energy")
        model.setDetail(\.number, to: " F-1234 ")
        model.setDetail(\.issuer, to: "   ")
        #expect(model.scan.details == DocumentDetails(number: "F-1234"))
    }

    @Test func editingOnlyTheDateLearnsNothing() async throws {
        let fixture = try Fixture()
        var scan = Scan(name: "Scan")
        scan.issuerKeys = ["lumen"]
        let model = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)
        model.setDetails(DocumentDetails(date: .now))
        #expect(fixture.settings.value.learnedIssuers.isEmpty)
        model.setDetails(DocumentDetails(category: .invoice, date: .now))
        #expect(fixture.settings.learnedIssuer(for: ["lumen"])?.category == .invoice)
    }

    @Test func readsTheFirstPageAgainWithTheNextPageWhenReadingItFailed() async throws {
        let fixture = try Fixture()
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "INVOICE").render(), quality: 0.9))
        let model = fixture.scanModel()
        let fallback = model.scan.title
        let reads = Counter()
        let processor = fixture.processor
        model.readDocument = { page, scanID, owners in
            guard reads.next() > 1 else { throw CancellationError() }
            return try await processor.detectDocument(on: page, scanID: scanID, owners: owners)
        }
        model.addPhoto(photo, liveQuad: nil)
        await model.waitUntilIdle()
        #expect(model.scan.read == nil)
        #expect(model.scan.title == fallback)

        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await model.waitUntilIdle()
        #expect(model.scan.read != nil)
        #expect(model.scan.title != fallback)
        #expect(fixture.store.all().first?.title == model.scan.title)

        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await model.waitUntilIdle()
        #expect(reads.count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func readsTheFirstPageAgainOnceTheAppIsActiveWhenReadingItFailedWhileItWasNot() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let model = fixture.scanModel()
        let fallback = model.scan.title
        let reads = Counter()
        let gate = fixture.processor.gate
        let lines = textLines(["LUMEN ENERGY SAS", "Invoice", "FERNWOOD SAS"])
        model.readDocument = { _, _, owners in
            guard reads.next() > 1 else {
                gate.isPaused = true
                throw CancellationError()
            }
            return DocumentDetector().detect(lines: lines, owners: owners)
        }
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        try await fixture.waitUntilGateHasWaiting(1)
        #expect(model.processing == 0)
        #expect(model.isReading)
        #expect(model.scan.title == fallback)

        gate.isPaused = false
        await model.waitUntilIdle()
        #expect(reads.count == 2)
        #expect(model.scan.read != nil)
        #expect(model.scan.title != fallback)
        #expect(model.owner.id == holding.id)
        #expect(!model.isReading)
    }

    @Test(.timeLimit(.minutes(1)))
    func isReadingFromTheFirstPhotoUntilThePageIsRead() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        #expect(!model.isReading)
        let reading = holdReading(of: model, reading: ["LUMEN ENERGY SAS", "Invoice"])

        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        #expect(model.isReading)
        for await _ in reading.started { break }
        #expect(model.processing == 0)
        #expect(model.isReading)

        reading.release()
        await model.waitUntilIdle()
        #expect(model.scan.read != nil)
        #expect(!model.isReading)
    }

    @Test(.timeLimit(.minutes(1)))
    func isReadingAgainWhileTheNextPageIsReadAfterReadingFailed() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.readDocument = { _, _, _ in throw CancellationError() }
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await model.waitUntilIdle()
        #expect(model.scan.read == nil)
        #expect(!model.isReading)

        let reading = holdReading(of: model, reading: ["LUMEN ENERGY SAS", "Invoice"])
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        #expect(model.isReading)
        for await _ in reading.started { break }
        #expect(model.processing == 0)
        #expect(model.isReading)

        reading.release()
        await model.waitUntilIdle()
        #expect(model.scan.read != nil)
        #expect(!model.isReading)
    }

    @Test func aStoredScanNeverReadIsNotBeingRead() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.readDocument = { _, _, _ in nil }
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await model.waitUntilIdle()

        let reopened = ScanModel(scan: try #require(fixture.store.all().first), processor: fixture.processor, settings: fixture.settings)
        #expect(reopened.scan.pages.count == 1)
        #expect(reopened.scan.read == nil)
        #expect(!reopened.isReading)
    }

    @Test func anUntouchedIssuerOpenedBeforeThePageWasReadKeepsTheIssuerRead() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        let shownIssuer = model.scan.details.issuer ?? ""
        model.readDocument = { [lines = textLines(["LUMEN ENERGY SAS", "Invoice"])] _, _, owners in DocumentDetector().detect(lines: lines, owners: owners) }
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        await model.waitUntilIdle()
        try #require(model.scan.details.issuer == "Lumen Energy")

        model.applyDetail(\.issuer, to: shownIssuer, shownText: shownIssuer)
        #expect(model.scan.details.issuer == "Lumen Energy")
        #expect(!model.scan.areDetailsEditedByUser)

        model.applyDetail(\.issuer, to: "", shownText: "Lumen Energy")
        #expect(model.scan.details.issuer == nil)
        #expect(model.scan.areDetailsEditedByUser)
    }

    @Test func closingTheSheetWithoutChangesKeepsWhatWasReadMeanwhile() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        let shownName = model.scan.title
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "INVOICE").render(), quality: 0.9))
        model.addPhoto(photo, liveQuad: nil)
        await model.waitUntilIdle()
        let read = model.scan.title
        try #require(read != shownName)

        model.applyName(shownName, shownName: shownName)
        #expect(model.scan.title == read)
        #expect(!model.scan.isNamedByUser)

        model.applyName("Mine", shownName: read)
        #expect(model.scan.title == "Mine")
        #expect(model.scan.isNamedByUser)
    }
}

private final class Counter: Sendable {
    private let value = Mutex(0)

    var count: Int { value.withLock { $0 } }

    func next() -> Int {
        value.withLock { value in
            value += 1
            return value
        }
    }
}

/// Follows the PDF builds of a scan model, and holds them until released.
private final class PDFBuilds: Sendable {
    private struct State {
        var count = 0
        var running = 0
        var mostAtOnce = 0
        var started: [CheckedContinuation<Void, Never>] = []
        var isReleased = false
        var released: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    var count: Int { state.withLock(\.count) }
    var mostAtOnce: Int { state.withLock(\.mostAtOnce) }

    func start() {
        let waiting = state.withLock { state in
            state.count += 1
            state.running += 1
            state.mostAtOnce = max(state.mostAtOnce, state.running)
            defer { state.started = [] }
            return state.started
        }
        waiting.forEach { $0.resume() }
    }

    func finish() {
        state.withLock { $0.running -= 1 }
    }

    /// Waits until that many builds started.
    func waitForStart(of count: Int = 1) async {
        while state.withLock({ $0.count < count }) {
            await withCheckedContinuation { continuation in
                let started = state.withLock { state in
                    if state.count >= count { return true }
                    state.started.append(continuation)
                    return false
                }
                if started { continuation.resume() }
            }
        }
    }

    func release() {
        let waiting = state.withLock { state in
            state.isReleased = true
            defer { state.released = [] }
            return state.released
        }
        waiting.forEach { $0.resume() }
    }

    func waitForRelease() async {
        await withCheckedContinuation { continuation in
            let released = state.withLock { state in
                if state.isReleased { return true }
                state.released.append(continuation)
                return false
            }
            if released { continuation.resume() }
        }
    }
}
