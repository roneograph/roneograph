import Foundation
import ScannerKit
import ScannerModels
import Testing

struct WordingTests {
    @Test func listsRememberedValuesInAFixedOrder() {
        #expect([RememberedValue.category].listed == "Category")
        #expect([RememberedValue.category, .name].listed == "Name and category")
        #expect(Set(RememberedValue.allCases).listed == "Name, category and issuer")
    }

    @Test func countsInTheSingularOnlyForOne() {
        #expect(0.counted("page") == "0 pages")
        #expect(1.counted("page") == "1 page")
        #expect(30.counted("day") == "30 days")
    }

    @Test func labelsRetentions() {
        #expect(ScanRetention.allCases.map(\.label) == ["1 day", "7 days", "30 days", "Forever"])
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
        payslip.sent = Date()
        payslip.sentBy = .files
        #expect([bill, payslip].alreadySent == "“Payslip” was already saved")
        #expect([payslip, payslip].alreadySent == "2 were already sent")
    }
}
