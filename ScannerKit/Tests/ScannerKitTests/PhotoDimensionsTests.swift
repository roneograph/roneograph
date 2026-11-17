import CoreMedia
import ScannerKit
import Testing

struct PhotoDimensionsTests {
    @Test func takesTheLargestSizeUpTo12Megapixels() {
        let sizes = [CMVideoDimensions(width: 8064, height: 6048), CMVideoDimensions(width: 4032, height: 3024), CMVideoDimensions(width: 1920, height: 1440)]
        #expect(CMVideoDimensions.photoSize(among: sizes).map { [$0.width, $0.height] } == [4032, 3024])
    }

    @Test func takesTheSmallestSizeWhenAllAreLarger() {
        let sizes = [CMVideoDimensions(width: 8064, height: 6048), CMVideoDimensions(width: 5712, height: 4284)]
        #expect(CMVideoDimensions.photoSize(among: sizes).map { [$0.width, $0.height] } == [5712, 4284])
    }

    @Test func takesNothingWithoutSizes() {
        #expect(CMVideoDimensions.photoSize(among: []).map { [$0.width, $0.height] } == nil)
    }
}
