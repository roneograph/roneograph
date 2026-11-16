import CoreGraphics
import ScannerKit
import Testing

struct ImageViewMappingTests {
    @Test func leavesBarsAboveAndBelowInATallView() {
        let mapping = ImageViewMapping(imageSize: CGSize(width: 300, height: 400), viewSize: CGSize(width: 300, height: 600))
        #expect(mapping.viewPoint(for: CGPoint(x: 0, y: 0)) == CGPoint(x: 0, y: 100))
        #expect(mapping.viewPoint(for: CGPoint(x: 1, y: 1)) == CGPoint(x: 300, y: 500))
        #expect(mapping.imageFrame == CGRect(x: 0, y: 100, width: 300, height: 400))
    }

    @Test func leavesBarsOnTheSidesInAWideView() {
        let mapping = ImageViewMapping(imageSize: CGSize(width: 300, height: 400), viewSize: CGSize(width: 600, height: 200))
        #expect(mapping.imageFrame == CGRect(x: 225, y: 0, width: 150, height: 200))
        #expect(mapping.viewPoint(for: CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 300, y: 100))
        #expect(mapping.viewPoint(for: CGPoint(x: 1, y: 1)) == CGPoint(x: 375, y: 200))
    }
}
