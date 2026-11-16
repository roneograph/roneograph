import CoreImage
import Foundation
import ScannerKit
import ScannerKitTesting
import Testing

struct TextReaderTests {
    @Test func readsTheLinesWithFramesFromTheTopLeft() async throws {
        let lines = await TextReader().lines(in: SyntheticPage().render())
        #expect(lines.count == 30)
        let first = try #require(lines.first)
        #expect(first.text == "The quick brown fox jumps over the lazy dog")
        #expect(first.frame.minY < 0.15)
        #expect(first.frame.minX < 0.1)
    }

    @Test(.timeLimit(.minutes(1)))
    func readsMorePagesAtOnceThanThereAreThreads() async {
        let page = SyntheticPage(lines: 5).render()
        let counts = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<ProcessInfo.processInfo.activeProcessorCount + 2 {
                group.addTask { await TextReader().lines(in: page).count }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(counts.count == ProcessInfo.processInfo.activeProcessorCount + 2)
        #expect(counts.allSatisfy { $0 > 0 })
    }
}
