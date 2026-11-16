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
        page.revision += 1
        #expect(cache.lines(of: page, read: read).first?.text == "Read 2")
        #expect(cache.lines(of: ScanPage(quad: nil, analysis: .sample), read: read).first?.text == "Read 3")
        #expect(reads == 3)
    }

    @Test func keepsOnlyTheLatestRevisionOfAPage() {
        let cache = PageTextCache()
        let original = ScanPage(quad: nil, analysis: .sample)
        var changed = original
        changed.revision += 1
        var reads = 0
        let read = { () -> [TextLine] in
            reads += 1
            return [TextLine(text: "Read \(reads)", frame: .zero)]
        }

        _ = cache.lines(of: original, read: read)
        _ = cache.lines(of: changed, read: read)
        #expect(cache.lines(of: original, read: read).first?.text == "Read 3")
    }
}
