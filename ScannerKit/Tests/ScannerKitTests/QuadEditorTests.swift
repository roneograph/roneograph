import CoreGraphics
import ScannerKit
import Testing

struct QuadEditorTests {
    let editor = QuadEditor()
    let page = Quad.rect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

    @Test func movesACorner() {
        let moved = editor.moving(.corner(0), in: page, to: CGPoint(x: 0.1, y: 0.15))
        #expect(moved.topLeft == CGPoint(x: 0.1, y: 0.15))
        #expect(moved.bottomRight == page.bottomRight)
    }

    @Test func keepsCornersInsideTheImage() {
        let moved = editor.moving(.corner(2), in: page, to: CGPoint(x: 1.3, y: 1.1))
        #expect(moved.bottomRight == CGPoint(x: 1, y: 1))
    }

    @Test func snapsToNearbyTargets() {
        let target = CGPoint(x: 0.12, y: 0.11)
        #expect(editor.moving(.corner(0), in: page, to: CGPoint(x: 0.13, y: 0.12), snapTargets: [target]).topLeft == target)
        #expect(editor.moving(.corner(0), in: page, to: CGPoint(x: 0.17, y: 0.12), snapTargets: [target]).topLeft == CGPoint(x: 0.17, y: 0.12))
    }

    @Test func refusesToFoldTheOutline() {
        #expect(editor.moving(.corner(0), in: page, to: CGPoint(x: 0.9, y: 0.9)) == page)
    }

    @Test func refusesATinyOutline() {
        let small = Quad.rect(x: 0.4, y: 0.4, width: 0.12, height: 0.12)
        #expect(editor.moving(.corner(2), in: small, to: CGPoint(x: 0.45, y: 0.45)) == small)
    }

    @Test func movesASideWithBothCorners() {
        let moved = editor.moving(.side(1), in: page, to: CGPoint(x: 0.9, y: 0.5))
        #expect(abs(moved.topRight.x - 0.9) < 1e-9 && abs(moved.bottomRight.x - 0.9) < 1e-9)
        #expect(moved.topLeft == page.topLeft)
    }

    @Test func keepsASideInsideTheImage() {
        let moved = editor.moving(.side(0), in: page, to: CGPoint(x: 0.5, y: -0.4))
        #expect(moved.topLeft.y == 0 && moved.topRight.y == 0)
        #expect(abs(moved.topLeft.x - 0.2) < 1e-9)
    }

    @Test func sideHandlesSitInTheMiddle() {
        #expect(editor.position(of: .side(2), in: page) == CGPoint(x: 0.5, y: 0.8))
    }

    @Test func convexity() {
        #expect(page.isConvex)
        #expect(Quad.full.isConvex)
        let bowtie = Quad(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 1, y: 1), bottomRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 1))
        #expect(!bowtie.isConvex)
    }

    @Test func mapsViewPointsBackToTheImage() {
        let mapping = ImageViewMapping(imageSize: CGSize(width: 300, height: 400), viewSize: CGSize(width: 300, height: 600), scaling: .fit)
        let point = CGPoint(x: 0.25, y: 0.75)
        let back = mapping.normalizedPoint(for: mapping.viewPoint(for: point))
        #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9)
        #expect(mapping.imageFrame == CGRect(x: 0, y: 100, width: 300, height: 400))
    }
}
