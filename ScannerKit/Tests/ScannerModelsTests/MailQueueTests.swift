import Foundation
import ScannerKit
import ScannerModels
import Testing

@MainActor
struct MailQueueTests {
    @Test func emailsOneMailPerOwnerToItsAddress() async throws {
        let fixture = try Fixture()
        fixture.settings.value.defaultOwner.email = "me@example.com"
        var holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        holding.email = "accounting@fernwood.example"
        fixture.settings.value.updateOwner(holding)
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let mine = await fixture.capturedScan(in: app)
        let theirs = await fixture.capturedScan(in: app)
        let other = await fixture.capturedScan(in: app)
        theirs.setOwner(holding.id)

        var mails = MailQueue([mine, theirs, other], app: app)
        #expect(mails.scans.map(\.id) == [mine.id, other.id])
        #expect(mails.recipient == "me@example.com")
        #expect(mails.closeMail(sent: true).map(\.id) == [mine.id, other.id])
        #expect(mine.scan.sent?.method == .email)
        #expect(app.toast == "2 scans emailed to me@example.com")

        #expect(mails.scans.map(\.id) == [theirs.id])
        #expect(mails.recipient == "accounting@fernwood.example")
        #expect(mails.closeMail(sent: true).map(\.id) == [theirs.id])
        #expect(mails.scans.isEmpty)
    }

    @Test func stopsAtTheFirstCancelledMail() async throws {
        let fixture = try Fixture()
        let holding = try #require(fixture.settings.addOwner("Fernwood Holding"))
        let app = AppModel(processor: fixture.processor, settings: fixture.settings)
        let theirs = await fixture.capturedScan(in: app)
        let mine = await fixture.capturedScan(in: app)
        theirs.setOwner(holding.id)

        var mails = MailQueue([theirs, mine], app: app)
        #expect(mails.recipient == nil)
        #expect(mails.closeMail(sent: false).isEmpty)
        #expect(mails.scans.isEmpty)
        #expect(theirs.scan.sent == nil)
        #expect(mine.scan.sent == nil)
        #expect(MailQueue([], app: app).scans.isEmpty)
    }
}
