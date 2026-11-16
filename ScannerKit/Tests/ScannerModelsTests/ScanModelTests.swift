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

    @Test func saysWhenAPageCannotBeProcessed() async throws {
        let fixture = try Fixture()
        let model = fixture.scanModel()
        model.addPhoto(Data("not a photo".utf8), liveQuad: nil)
        await model.waitUntilIdle()
        #expect(model.failure == "A page could not be processed.")
        #expect(model.processing == 0)
        #expect(model.scan.pages.isEmpty)
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

    @Test func deletingTheLastPageLeavesNothingBehind() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        await model.buildPDF(delay: .zero)
        #expect(fixture.pdfExists(model.scan.fileName))

        model.deletePage(model.scan.pages[0].id)
        await model.waitUntilIdle()

        #expect(fixture.store.all().isEmpty)
        #expect(!fixture.pdfExists(model.scan.fileName))
        #expect(!FileManager.default.fileExists(atPath: fixture.store.directory(of: model.id).path(percentEncoded: false)))
    }

    @Test func deletingTheLastPageKeepsAPageStillProcessed() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        model.deletePage(model.scan.pages[0].id)
        await model.waitUntilIdle()

        let page = try #require(model.scan.pages.first)
        #expect(fixture.store.all().first?.pages == [page])
        #expect(FileManager.default.fileExists(atPath: model.previewURL(of: page).path(percentEncoded: false)))
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
        try FileManager.default.removeItem(at: url)
        await model.preparePDF()
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

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

    @Test func editedDetailsRenameTheFileWithACustomFormat() async throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.fileNameFormat = FileNameFormat(isCustom: true, template: "{CATEGORY}/{YYYY} {ISSUER} {NUMBER}")
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

    @Test func aRememberedOwnerIsNotUsedWithASingleOwner() async throws {
        let fixture = try Fixture()
        let photo = try #require(PageExtractor(context: CIContext()).jpegData(of: SyntheticPage(title: "LUMEN ENERGY SAS").render(), quality: 0.9))
        let first = fixture.scanModel()
        first.addPhoto(photo, liveQuad: nil)
        await first.waitUntilIdle()
        fixture.settings.learn(keys: first.scan.issuerKeys) { $0.owner = UUID() }

        let second = fixture.scanModel()
        second.addPhoto(photo, liveQuad: nil)
        await second.waitUntilIdle()
        #expect(second.hasDefaultOwner)
        #expect(second.scan.remembered.isEmpty)
    }

    @Test func sendingLinksTheLinesOfThePageToItsOwner() throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        fixture.settings.recordHeaderLines(["fernwood holding"], issuerEvidence: ["print.example"])
        var scan = Scan(name: "Scan")
        scan.headerLines = ["fernwood holding"]
        scan.owner = holding.id
        let model = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)

        model.markSent(.email)
        #expect(fixture.settings.value.headerLines.first?.owners == [holding.id])
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
