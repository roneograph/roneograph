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

    @Test func labelsRetentions() {
        #expect(ScanRetention.allCases.map(\.label) == ["1 day", "7 days", "30 days", "Forever"])
    }

    @Test func mentionsOwnersOnlyWhenThereAreSeveral() {
        var settings = ScannerSettings()
        #expect(settings.emailQuestionTitle(for: settings.defaultOwnerID) == "Email scans to")
        #expect(settings.nothingRemembered == "Correct the name, issuer or category of a scan, and it is reused for the next documents from the same issuer.")
        #expect(settings.forgetEverythingMessage == "Corrections for 0 issuers, and which lines are your name and address. Scans and settings stay.")
        let holding = Owner(name: "Fernwood Holding")
        settings.addOwner(holding)
        #expect(settings.emailQuestionTitle(for: holding.id) == "Email Fernwood Holding scans to")
        #expect(settings.emailQuestionTitle(for: nil) == "Email Personal scans to")
        #expect(settings.nothingRemembered == "Correct the name, issuer, category or owner of a scan, and it is reused for the next documents from the same issuer.")
        settings.learnedIssuers = [LearnedIssuer(keys: ["lumen"], owner: holding.id)]
        #expect(settings.forgetEverythingMessage == "Corrections and owners remembered for 1 issuer, which lines are your name and address, and which lines tell each owner. Scans, owners and settings stay.")
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
        #expect(scan.status == "In progress · 1 page")
        scan.isFinished = true
        #expect(scan.status == "Not sent · now · 1 page")
        scan.sent = Sent(date: Date(), method: .share)
        #expect(scan.status == "Shared now · 1 page")
        scan.sent = Sent(date: Date().addingTimeInterval(-3 * 86400), method: .share)
        #expect(scan.status.hasPrefix("Shared "))
        #expect(!scan.status.contains("now"))
    }

    @MainActor
    @Test func summarizesThePDFsToSend() async throws {
        let fixture = try Fixture()
        let first = await fixture.scanModel(pages: 1)
        let second = await fixture.scanModel(pages: 2)
        #expect([ScanModel]().selectionSummary == "Select the scans to send")
        #expect(second.summary == "2 pages · preparing the PDF…")
        #expect([first, second].selectionSummary == "2 documents · 3 pages · preparing the PDFs…")

        await first.preparePDF()
        await second.preparePDF()
        guard case .ready(_, let firstSize) = first.pdf, case .ready(_, let secondSize) = second.pdf else {
            Issue.record("PDFs not ready")
            return
        }
        #expect(second.summary == "2 pages · \(ByteCountFormatter.string(fromByteCount: Int64(secondSize), countStyle: .file))")
        #expect([first, second].selectionSummary == "2 documents · 3 pages · \(ByteCountFormatter.string(fromByteCount: Int64(firstSize + secondSize), countStyle: .file))")

        second.rename("Water bill")
        #expect(second.summary == "2 pages · preparing the PDF…")
    }

    @MainActor
    @Test func saysThereAreNoPagesOnceTheLastOneIsDeleted() async throws {
        let fixture = try Fixture()
        let model = await fixture.scanModel(pages: 1)
        model.deletePage(model.scan.pages[0].id)
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
            for page in model.scan.pages { try FileManager.default.removeItem(at: fixture.store.flatURL(scanID: model.id, pageID: page.id)) }
        }
        await second.preparePDF()
        #expect(second.summary == "1 page · the PDF could not be made")
        #expect([second].selectionSummary == "1 document · 1 page · the PDF could not be made")
        #expect([first, second].selectionSummary == "2 documents · 2 pages · a PDF could not be made")
        await first.buildPDF(delay: .zero)
        #expect([first, second].selectionSummary == "2 documents · 2 pages · 2 PDFs could not be made")
    }

    @Test func namesPageLooks() {
        #expect(PageLook.allCases.map(\.title) == ["Gray", "Color"])
    }

    @Test func namesTheMailAfterTheScanOrCountsTheDocuments() {
        let bill = Scan(name: "bill", title: "Water bill")
        #expect([bill].mailSubject == "Water bill")
        #expect([bill, Scan(name: "letter", title: "Letter")].mailSubject == "2 documents")
    }

    @Test func warnsAboutScansAlreadySent() {
        var payslip = Scan(name: "payslip", title: "Payslip")
        let bill = Scan(name: "bill", title: "Water bill")
        #expect([bill].alreadySent == nil)
        payslip.sent = Sent(date: Date(), method: .files)
        #expect([bill, payslip].alreadySent == "“Payslip” was already saved")
        #expect([payslip, payslip].alreadySent == "2 were already sent")
    }
}
