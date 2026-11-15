import ScannerKit
import ScannerModels
import Testing

struct WordingTests {
    @Test func countsInTheSingularOnlyForOne() {
        #expect(0.counted("page") == "0 pages")
        #expect(1.counted("page") == "1 page")
        #expect(30.counted("day") == "30 days")
    }
}
