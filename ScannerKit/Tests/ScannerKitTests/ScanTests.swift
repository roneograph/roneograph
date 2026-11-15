import CoreImage
import ScannerKit
import ScannerKitTesting
import Testing

struct ScanTests {
    @Test func turnsAQuarterTurnEitherWay() {
        #expect(PageOrientation.up.turned(clockwise: true) == .right)
        #expect(PageOrientation.up.turned(clockwise: false) == .left)
        for orientation in PageOrientation.allCases {
            #expect(orientation.turned(clockwise: true).turned(clockwise: false) == orientation)
            #expect(orientation.turned(clockwise: true).turned(clockwise: true) != orientation)
        }
    }

    @Test func rotatingAPageBumpsItsRevision() {
        var page = ScanPage(quad: nil, analysis: .sample)
        page.rotate(clockwise: false)
        #expect(page.analysis.orientation == .left)
        #expect(page.revision == 1)
    }

    @Test func aPageTurnedClockwiseRendersSideways() {
        let cleaner = PageCleaner(context: CIContext())
        let flat = SyntheticPage().render()
        var page = ScanPage(quad: nil, analysis: cleaner.analyze(flat))
        page.rotate(clockwise: true)
        let turned = cleaner.render(flat, analysis: page.analysis, settings: page.cleanup)
        #expect(turned.extent.width > turned.extent.height)
        #expect(cleaner.analyze(turned).orientation == .left)
    }
}
