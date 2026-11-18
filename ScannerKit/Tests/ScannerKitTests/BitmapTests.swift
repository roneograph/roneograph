import CoreImage
@testable import ScannerKit
import Testing

struct BitmapTests {
    @Test func keepsTheEdgesOfAWhiteImageWhite() {
        let white = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1001, height: 1415))
        let bitmap = Bitmap(white, longSide: 256, context: CIContext())
        let luminances = (0..<bitmap.count).map(bitmap.luminance)
        #expect(luminances.allSatisfy { abs($0 - 1) < 0.001 }, "darkest pixel \(luminances.min() ?? 0)")
    }
}
