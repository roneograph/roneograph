import Foundation
import ScannerKit
import ScannerKitTesting
import Testing

struct PageTextCacheTests {
    @Test func readsEachPageRevisionOnce() {
        let cache = PageTextCache()
        var page = ScanPage(quad: nil, analysis: .sample)
        var reads = 0
        let read = { () -> [TextLine] in
            reads += 1
            return [TextLine(text: "Read \(reads)", frame: .zero)]
        }

        #expect(cache.lines(of: page, read: read).first?.text == "Read 1")
        #expect(cache.lines(of: page, read: read).first?.text == "Read 1")
        page.rotate()
        #expect(cache.lines(of: page, read: read).first?.text == "Read 2")
        #expect(cache.lines(of: ScanPage(quad: nil, analysis: .sample), read: read).first?.text == "Read 3")
        #expect(reads == 3)
    }
}
