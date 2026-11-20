import CoreGraphics
import CoreImage
@testable import ScannerKit
import ScannerKitTesting
import Testing

struct PageUnwarperTests {
    let context = CIContext()

    @Test func flattensAFlatPageLikeItsCorners() async throws {
        let photo = SyntheticPhoto.render(page: .tilted)
        let corrected = PageExtractor(context: context).correct(photo, quad: .tilted)
        let unwarped = try #require(await PageUnwarper(context: context).unwarp(photo, quad: .tilted, size: corrected.extent.size))
        #expect(unwarped.extent == corrected.extent)
        let expected = inkBounds(PixelBuffer(corrected, context: context)), found = inkBounds(PixelBuffer(unwarped, context: context))
        let tolerance = 0.02 * corrected.extent.width
        #expect(abs(found.minX - expected.minX) < tolerance && abs(found.maxX - expected.maxX) < tolerance, "ink from \(found) instead of \(expected)")
        #expect(abs(found.minY - expected.minY) < tolerance && abs(found.maxY - expected.maxY) < tolerance, "ink from \(found) instead of \(expected)")
    }

    @Test func leavesNoDeskAlongTheEdges() async throws {
        let photo = SyntheticPhoto.render(page: .tilted)
        let size = PageExtractor(context: context).correct(photo, quad: .tilted).extent.size
        let page = PixelBuffer(try #require(await PageUnwarper(context: context).unwarp(photo, quad: .tilted, size: size)), context: context)
        let inset = 4
        let edges = (inset..<(page.height - inset)).flatMap { [gray(page, inset, $0), gray(page, page.width - 1 - inset, $0)] }
        #expect(Bitmap.percentile(edges, 0.05) > 180, "darkest edges \(Bitmap.percentile(edges, 0.05))")
    }

    @Test func cropsAroundTheOutlineWithAMarginInsideThePhoto() {
        let size = CGSize(width: 1000, height: 2000)
        #expect(PageUnwarper.cropRect(of: .rect(x: 0.2, y: 0.1, width: 0.5, height: 0.5), in: size) == CGRect(x: 185, y: 770, width: 530, height: 1060))
        #expect(PageUnwarper.cropRect(of: .full, in: size) == CGRect(origin: .zero, size: size))
    }

    @Test func anIdentityGridGivesTheSourceBack() {
        var source = PixelBuffer(width: 5, height: 4)
        for i in 0..<(5 * 4) { source.pixels[i * 4] = UInt8(i * 12) }
        let grid = UnwarpGrid(rows: 2, columns: 2, points: [SIMD2(-1, -1), SIMD2(1, -1), SIMD2(-1, 1), SIMD2(1, 1)])
        #expect(grid.warp(source, width: 5, height: 4).pixels == source.pixels)
    }

    @Test func aGridOverTheLeftHalfStretchesIt() {
        var source = PixelBuffer(width: 3, height: 1)
        source.pixels.replaceSubrange(0..<12, with: [0, 0, 0, 255, 100, 100, 100, 255, 200, 200, 200, 255])
        let grid = UnwarpGrid(rows: 2, columns: 2, points: [SIMD2(-1, -1), SIMD2(0, -1), SIMD2(-1, 1), SIMD2(0, 1)])
        let output = grid.warp(source, width: 3, height: 1)
        #expect(stride(from: 0, to: 12, by: 4).map { output.pixels[$0] } == [0, 50, 100])
    }

    private func gray(_ buffer: PixelBuffer, _ x: Int, _ y: Int) -> Float {
        let i = (y * buffer.width + x) * 4
        return (Float(buffer.pixels[i]) + Float(buffer.pixels[i + 1]) + Float(buffer.pixels[i + 2])) / 3
    }

    /// The box around the dark pixels, away from the outer edges where the corrected page shows a sliver of desk.
    private func inkBounds(_ buffer: PixelBuffer) -> CGRect {
        let inset = buffer.width / 20
        var minX = buffer.width, maxX = 0, minY = buffer.height, maxY = 0
        for y in inset..<(buffer.height - inset) {
            for x in inset..<(buffer.width - inset) where gray(buffer, x, y) < 100 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
