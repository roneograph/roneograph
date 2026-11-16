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

    @Test func rotatingAPageBumpsItsRevision() {
        var page = ScanPage(quad: nil, analysis: .sample)
        page.rotate()
        #expect(page.analysis.orientation == .right)
        #expect(page.revision == 1)
    }

    @Test func aPageTurnedClockwiseRendersSideways() {
        let cleaner = PageCleaner(context: CIContext())
        let flat = SyntheticPage().render()
        var page = ScanPage(quad: nil, analysis: cleaner.analyze(flat))
        page.rotate()
        let turned = cleaner.render(flat, analysis: page.analysis, settings: page.cleanup)
        #expect(turned.extent.width > turned.extent.height)
        #expect(cleaner.analyze(turned).orientation == .left)
    }

    @Test func readsTheDocumentDateOfOlderScansAsADetail() throws {
        let json = #"{"id":"9F1C2D3E-0000-4000-8000-000000000001","created":"2026-11-15T10:00:00Z","name":"Invoice","title":"Invoice","documentDate":"2026-11-12T12:00:00Z","isNamedByUser":false,"suggestions":["Invoice"],"pages":[],"isFinished":true}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scan = try decoder.decode(Scan.self, from: Data(json.utf8))
        #expect(scan.details == DocumentDetails(date: ISO8601DateFormatter().date(from: "2026-11-12T12:00:00Z")))
        #expect(scan.suggestedParts == SuggestedParts())
    }

    @Test func theFileNameLeavesTheFoldersOut() {
        #expect(Scan(name: "Invoice/2026 Lumen").fileName == "2026 Lumen")
        #expect(Scan(name: "Lumen").fileName == "Lumen")
    }
}
