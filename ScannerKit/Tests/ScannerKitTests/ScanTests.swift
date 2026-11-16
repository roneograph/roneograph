import CoreImage
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
}
