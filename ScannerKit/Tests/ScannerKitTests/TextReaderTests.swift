import CoreImage
import ScannerKit
import ScannerKitTesting
import Testing

struct TextReaderTests {
    @Test func readsTheLinesWithFramesFromTheTopLeft() throws {
        let lines = TextReader().lines(in: SyntheticPage().render())
        #expect(lines.count == 30)
        let first = try #require(lines.first)
        #expect(first.text == "The quick brown fox jumps over the lazy dog")
        #expect(first.frame.minY < 0.15)
        #expect(first.frame.minX < 0.1)
    }
}
