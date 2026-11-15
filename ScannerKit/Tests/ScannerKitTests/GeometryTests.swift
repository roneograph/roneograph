import CoreGraphics
import ScannerKit
import Testing

struct GeometryTests {
    @Test func visionPointsAreFlipped() {
        let quad = Quad(lowerLeftOriginTopLeft: CGPoint(x: 0.1, y: 0.9), topRight: CGPoint(x: 0.9, y: 0.8), bottomRight: CGPoint(x: 0.8, y: 0.1), bottomLeft: CGPoint(x: 0.2, y: 0.2))
        #expect(abs(quad.topLeft.y - 0.1) < 1e-9)
        #expect(abs(quad.topRight.y - 0.2) < 1e-9)
        #expect(abs(quad.bottomRight.y - 0.9) < 1e-9)
        #expect(abs(quad.bottomLeft.y - 0.8) < 1e-9)
    }

    @Test func area() {
        let square = Quad.rect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        #expect(abs(square.area - 0.25) < 1e-9)
    }

    @Test func maxCornerDistance() {
        let a = Quad.rect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        var b = a
        b.bottomRight.x += 0.03
        b.bottomRight.y += 0.04
        #expect(abs(a.maxCornerDistance(to: b) - 0.05) < 1e-9)
    }

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
