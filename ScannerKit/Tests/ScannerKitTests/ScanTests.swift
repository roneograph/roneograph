import CoreImage
import Foundation
import ScannerKit
import ScannerKitTesting
import Testing

struct ScanTests {
    @Test func turnsAQuarterTurnClockwise() {
        #expect(PageOrientation.up.turned == .right)
        for orientation in PageOrientation.allCases {
            #expect(orientation.turned != orientation)
            #expect(orientation.turned.turned.turned.turned == orientation)
        }
    }

    @Test func rotatesAPageAQuarterTurnClockwise() {
        var page = ScanPage(quad: nil, analysis: .sample)
        page.rotate()
        #expect(page.analysis.orientation == .right)
    }

    @Test func aPageTurnedClockwiseRendersSideways() async throws {
        let cleaner = PageCleaner(context: CIContext())
        let flat = SyntheticPage().render()
        var page = ScanPage(quad: nil, analysis: try await cleaner.analyze(flat))
        page.rotate()
        let turned = cleaner.render(flat, analysis: page.analysis, look: page.look)
        #expect(turned.extent.width > turned.extent.height)
        #expect(try await cleaner.analyze(turned).orientation == .left)
    }

    @Test func keepsWhatWasReadAndWhatIsRemembered() throws {
        var scan = Scan(name: "Invoice")
        scan.read = ReadDocument(details: DocumentDetails(category: .letter, issuer: "Lumen"), parts: SuggestedParts(type: "Invoice"))
        scan.remembered = [.name, .issuer]
        scan.sent = Sent(date: Date(timeIntervalSince1970: 1_794_700_000), method: .share)
        let decoded = try JSONDecoder().decode(Scan.self, from: JSONEncoder().encode(scan))
        #expect(decoded == scan)
    }

    @Test func storesTheCategoryAsItsName() throws {
        let details = DocumentDetails(category: .bankStatement)
        let json = try String(decoding: JSONEncoder().encode(details), as: UTF8.self)
        #expect(json == #"{"category":"Bank statement"}"#)
        #expect(try JSONDecoder().decode(DocumentDetails.self, from: Data(json.utf8)) == details)
    }

    @Test func theFileNameLeavesTheFoldersOut() {
        #expect(Scan(name: "Invoice/2026 Lumen").fileName == "2026 Lumen")
        #expect(Scan(name: "Lumen").fileName == "Lumen")
    }
}
