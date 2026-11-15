import CoreGraphics
import ScannerKit
import Testing

struct ImageViewMappingTests {
    @Test func aspectFillCropsTheSidesOfATallView() {
        let mapping = ImageViewMapping(imageSize: CGSize(width: 300, height: 400), viewSize: CGSize(width: 300, height: 600), scaling: .fill)
        #expect(mapping.viewPoint(for: CGPoint(x: 0, y: 0)) == CGPoint(x: -75, y: 0))
        #expect(mapping.viewPoint(for: CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 150, y: 300))
        #expect(mapping.viewPoint(for: CGPoint(x: 1, y: 1)) == CGPoint(x: 375, y: 600))
    }

    @Test func aspectFitLeavesBarsAboveAndBelowInATallView() {
        let mapping = ImageViewMapping(imageSize: CGSize(width: 300, height: 400), viewSize: CGSize(width: 300, height: 600), scaling: .fit)
        #expect(mapping.viewPoint(for: CGPoint(x: 0, y: 0)) == CGPoint(x: 0, y: 100))
        #expect(mapping.viewPoint(for: CGPoint(x: 1, y: 1)) == CGPoint(x: 300, y: 500))
        #expect(mapping.imageFrame == CGRect(x: 0, y: 100, width: 300, height: 400))
    }

    @Test func aspectFillCropsTheTopOfAWideView() {
        let mapping = ImageViewMapping(imageSize: CGSize(width: 300, height: 400), viewSize: CGSize(width: 600, height: 400), scaling: .fill)
        #expect(mapping.viewPoint(for: CGPoint(x: 0, y: 0)) == CGPoint(x: 0, y: -200))
        #expect(mapping.viewPoint(for: CGPoint(x: 1, y: 1)) == CGPoint(x: 600, y: 600))
    }
}
