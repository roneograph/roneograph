import CoreImage
import Foundation
import ScannerKit
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
        #expect(!FileManager.default.fileExists(atPath: model.photoURL(of: page).path(percentEncoded: false)))
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
        fixture.settings.value.fileNameFormat = FileNameFormat(datePosition: .start, separator: .dash, lowercase: true)
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
        let created = ISO8601DateFormatter().date(from: "2026-11-12T12:00:00Z")!
        let model = ScanModel(scan: Scan(created: created, name: "Scan"), processor: fixture.processor, settings: fixture.settings)
        model.rename("   ")
        #expect(model.scan.title == "Scan 2026-11-12")
    }

    @Test func twoScansWithTheSameNameGetDifferentFiles() async throws {
        let fixture = try Fixture()
        fixture.settings.value.fileNameFormat = FileNameFormat(separator: .dash)
        let first = await fixture.scanModel(pages: 1)
        let second = await fixture.scanModel(pages: 1)
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

    @Test func reusesACorrectedNameWhenTheSameSuggestionComesBack() async throws {
        let fixture = try Fixture()
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "INVOICE").render(), quality: 0.9))
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
    }

    @Test func changingTheFormatRenamesTheFile() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.rename("Lumen invoice")
        fixture.settings.value.fileNameFormat = FileNameFormat(separator: .underscore, lowercase: true)
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

    @Test func editedDetailsRenameTheFileWithACustomFormat() async throws {
        let fixture = try Fixture()
        fixture.settings.value.fileNameFormat = FileNameFormat(isCustom: true, template: "{CATEGORY}/{YYYY} {ISSUER} {NUMBER}")
        let model = await fixture.scanModel(pages: 1)
        let year = String(FileNamer.isoDate(model.scan.created).prefix(4))
        await model.buildPDF(delay: .zero)
        model.setDetails(DocumentDetails(category: .insurance, issuer: "Acme Mutual", number: "P-1234"))
        #expect(model.scan.areDetailsEditedByUser)
        #expect(model.scan.name == "Insurance/\(year) Acme Mutual P-1234")
        #expect(fixture.pdfExists("\(year) Acme Mutual P-1234"))
        #expect(fixture.store.all().first?.details.issuer == "Acme Mutual")
    }

    @Test func aSuggestedNameLeavesOutTheDetailsTheFormatShows() throws {
        let fixture = try Fixture()
        fixture.settings.value.fileNameFormat = FileNameFormat(isCustom: true, template: "{CATEGORY} {ISSUER} {NAME}")
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

    @Test func tellsWhichSuggestionANameWouldBeLearnedFor() throws {
        let fixture = try Fixture()
        var scan = Scan(name: "Scan", title: "Invoice Lumen")
        scan.suggestions = ["Invoice Lumen", "Invoice 1234"]
        let model = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)
        #expect(model.learnedSuggestion(for: "Lumen electricity") == "Invoice Lumen")
        #expect(model.learnedSuggestion(for: "Invoice Lumen") == nil)
        #expect(fixture.scanModel().learnedSuggestion(for: "Mine") == nil)
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
