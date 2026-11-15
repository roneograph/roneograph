import CoreGraphics
import ScannerKit
import ScannerKitTesting
import Testing

struct QuadTests {
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

    @Test func convexity() {
        #expect(Quad.rect(x: 0.2, y: 0.2, width: 0.6, height: 0.6).isConvex)
        #expect(Quad.full.isConvex)
        let bowtie = Quad(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 1, y: 1), bottomRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 1))
        #expect(!bowtie.isConvex)
    }
}
