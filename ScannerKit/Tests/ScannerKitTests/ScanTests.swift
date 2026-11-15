import ScannerKit
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
}
