import Foundation
import ScannerKit
import ScannerKitTesting
import ScannerModels
import Testing

struct WordingTests {
    @Test func listsRememberedValuesInAFixedOrder() {
        #expect([RememberedValue.category].listed == "Category")
        #expect([RememberedValue.category, .name].listed == "Name and category")
        #expect(Set(RememberedValue.allCases).listed == "Name, category, issuer and owner")
    }

    @Test func countsInTheSingularOnlyForOne() {
        #expect(0.counted("page") == "0 pages")
        #expect(1.counted("page") == "1 page")
        #expect(30.counted("day") == "30 days")
    }

    @Test func mentionsOwnersOnlyWhenThereAreSeveral() {
        var settings = ScannerSettings()
        #expect(settings.nothingRemembered == "Correct the name, issuer or category of a scan, and it is reused for the next documents from the same issuer.")
        let holding = Owner(name: "Fernwood Holding")
        settings.addOwner(holding)
        #expect(settings.nothingRemembered == "Correct the name, issuer, category or owner of a scan, and it is reused for the next documents from the same issuer.")
    }

    @Test func explainsHowTheNamesOfAnOwnerAreRecognized() {
        var settings = ScannerSettings()
        let me = settings.defaultOwnerID
        #expect(settings.addressedToFooter(of: me, region: "FR", language: "en") == "Type your name above: documents addressed to you are then recognized.")
        settings.defaultOwner.name = "Camille Rouvière"
        #expect(settings.addressedToFooter(of: me, region: "FR", language: "en") == "Also recognized: C. Rouvière, Mme Rouvière, M. et Mme Rouvière, Famille Rouvière. Case, accents and word order do not matter.")
        let holding = Owner(name: "Fernwood Holding")
        settings.addOwner(holding)
        #expect(settings.addressedToFooter(of: holding.id, region: "FR", language: "en") == "Also recognized: Fernwood Holding SAS, Fernwood SAS, Fernwood. Case, accents and word order do not matter.")
        settings.defaultOwner.name = "Personal"
        #expect(settings.addressedToFooter(of: me, region: "FR", language: "en") == "Name this owner as on its mail, with a first and a last name: documents addressed to it are then recognized.")
    }

    @Test func warnsOfAnAddressAnotherOwnerHas() {
        var settings = ScannerSettings()
        settings.defaultOwner.name = "Camille Rouvière"
        settings.defaultOwner.addresses = ["8 rue des Glycines\n69007 Lyon"]
        var holding = Owner(name: "Fernwood Holding")
        holding.addresses = ["3 impasse des Tilleuls 38000 Grenoble"]
        settings.addOwner(holding)
        #expect(settings.sharedAddressWarning(of: holding.id) == nil)
        holding.addresses.append("8, rue des Glycines 69007 LYON")
        settings.updateOwner(holding)
        #expect(settings.sharedAddressWarning(of: holding.id) == "Camille Rouvière has this address too: only the names tell them apart.")
        var noe = Owner(name: "Noé Rouvière", symbol: .person)
        noe.addresses = ["8 rue des Glycines 69007 Lyon"]
        settings.addOwner(noe)
        #expect(settings.sharedAddressWarning(of: holding.id) == "Camille Rouvière and Noé Rouvière have this address too: only the names tell them apart.")
    }

    @Test func namesTheIssuerInSentences() {
        #expect(DocumentDetails(issuer: "Lumen Energy").issuerName == "Lumen Energy")
        #expect(DocumentDetails().issuerName == "this issuer")
    }

    @Test func explainsTheFileNameFormat() {
        #expect(FileNameFormat().explanation(for: []) == "Format in Settings: no date, spaces.")
        #expect(FileNameFormat(datePosition: .start, dateSource: .scan, separator: .dash, lowercase: true).explanation(for: []) == "Format in Settings: date of the scan first, dashes, lowercase.")
        #expect(FileNameFormat(datePosition: .end, separator: .underscore).explanation(for: []) == "Format in Settings: date of the document last, underscores.")
        #expect(FileNameFormat(isCustom: true, template: "{YYYY} {NAME}").explanation(for: []) == "Custom format in Settings: {YYYY} {NAME}")
        #expect(FileNameFormat(isCustom: true).explanation(for: [FileNameSegment("Invoice", .category), FileNameSegment("", .name)]) == "The format already shows what the suggested name says. Type a name to add to it.")
    }

    @MainActor
    @Test func saysWhatANameTeachesForTheIssuer() throws {
        let fixture = try Fixture()
        var scan = Scan(name: "Invoice Lumen Energy", title: "Invoice Lumen Energy")
        scan.suggestions = ["Invoice Lumen Energy"]
        scan.issuerKeys = ["lumen-energy.example"]
        scan.details = DocumentDetails(issuer: "Lumen Energy", date: ISO8601DateFormatter().date(from: "2026-11-12T12:00:00Z"), number: "F-1234")
        let model = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)
        #expect(model.learning(forName: "Invoice Lumen Energy") == nil)
        #expect(model.learning(forName: "Lumen bill") == "The next documents from Lumen Energy will be named the same way.")
        #expect(model.learning(forName: "Lumen bill November 2026 F-1234") == "The next documents from Lumen Energy will be named the same way, with their own date and number.")

        scan.title = "Lumen bill"
        scan.remembered = [.name]
        let remembered = ScanModel(scan: scan, processor: fixture.processor, settings: fixture.settings)
        #expect(remembered.learning(forName: "Lumen bill") == "The next documents from Lumen Energy will be named the same way.")
        #expect(remembered.learning(forName: "Lumen electricity") == "Replaces the name remembered for Lumen Energy. The next documents from Lumen Energy will be named the same way.")
        #expect(remembered.learning(forName: "Invoice Lumen Energy") == "The name remembered for Lumen Energy will be forgotten.")
        #expect(remembered.learning(forName: "") == "The name remembered for Lumen Energy will be forgotten.")
        #expect(remembered.learning(forName: " Lumen  bill ") == "The next documents from Lumen Energy will be named the same way.")
    }

    @Test func saysWhereEachScanIsOnHome() {
        var scan = Scan(name: "bill", title: "Water bill")
        scan.pages = [ScanPage(quad: nil, analysis: .sample)]
        #expect(scan.status == "Not sent · now · 1 page")
        scan.sent = Sent(date: Date(), method: .share)
        #expect(scan.status == "Shared now · 1 page")
        scan.sent = Sent(date: Date().addingTimeInterval(-3 * 86400), method: .share)
        #expect(scan.status.hasPrefix("Shared "))
        #expect(!scan.status.contains("now"))
    }

    @MainActor
    @Test func summarizesThePDFToSend() async throws {
        let fixture = try Fixture()
        let first = await fixture.scanModel(pages: 1)
        let second = await fixture.scanModel(pages: 2)
        #expect(second.summary == "2 pages · preparing the PDF…")

        await first.preparePDF()
        await second.preparePDF()
        guard case .ready = first.pdf, case .ready(_, let secondSize) = second.pdf else {
            Issue.record("PDFs not ready")
            return
        }
        #expect(second.summary == "2 pages · \(ByteCountFormatter.string(fromByteCount: Int64(secondSize), countStyle: .file))")

        second.rename("Water bill")
        #expect(second.summary == "2 pages · preparing the PDF…")
    }

    @MainActor
    @Test func saysThereAreNoPagesOnceTheLastOneIsDeleted() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.deleteCapturedPage(model.scan.pages[0].id)
        await model.waitUntilIdle()
        #expect(model.summary == "No pages")
    }

    @MainActor
    @Test func saysWhenAPDFCouldNotBeMade() async throws {
        let fixture = try Fixture()
        let first = await fixture.scanModel(pages: 1)
        let second = await fixture.scanModel(pages: 1)
        await first.preparePDF()
        for model in [first, second] {
            for page in model.scan.pages { try FileManager.default.removeItem(at: fixture.store.flatURL(scanID: model.id, page: page)) }
        }
        await second.preparePDF()
        #expect(second.summary == "1 page · the PDF could not be made")
    }

    @Test func namesPageLooks() {
        #expect(PageLook.allCases.map(\.title) == ["Gray", "Color"])
    }
}
