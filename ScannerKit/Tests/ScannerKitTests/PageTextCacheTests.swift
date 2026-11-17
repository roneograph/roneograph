import Foundation
import ScannerKit
import ScannerKitTesting
import Testing

struct PageTextCacheTests {
    @Test func readsEachPageRevisionOnce() async {
        let cache = PageTextCache()
        var page = ScanPage(quad: nil, analysis: .sample)
        var reads = 0
        let read = { () -> [TextLine] in
            reads += 1
            return [TextLine(text: "Read \(reads)", frame: .zero)]
        }

        #expect(await cache.lines(of: page, read: read).first?.text == "Read 1")
        #expect(await cache.lines(of: page, read: read).first?.text == "Read 1")
        page.revision += 1
        #expect(await cache.lines(of: page, read: read).first?.text == "Read 2")
        #expect(await cache.lines(of: ScanPage(quad: nil, analysis: .sample), read: read).first?.text == "Read 3")
        #expect(reads == 3)
    }

    @Test func readsAPageAgainAfterAFailedRead() async throws {
        struct Failure: Error {}
        let cache = PageTextCache()
        let page = ScanPage(quad: nil, analysis: .sample)
        await #expect(throws: Failure.self) { try await cache.lines(of: page) { throw Failure() } }
        #expect(await cache.lines(of: page) { [TextLine(text: "Read", frame: .zero)] }.first?.text == "Read")
    }

    @Test func keepsOnlyTheLatestRevisionOfAPage() async {
        let cache = PageTextCache()
        let original = ScanPage(quad: nil, analysis: .sample)
        var changed = original
        changed.revision += 1
        var reads = 0
        let read = { () -> [TextLine] in
            reads += 1
            return [TextLine(text: "Read \(reads)", frame: .zero)]
        }

        _ = await cache.lines(of: original, read: read)
        _ = await cache.lines(of: changed, read: read)
        #expect(await cache.lines(of: original, read: read).first?.text == "Read 3")
    }
}
