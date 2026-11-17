import CoreImage
import Foundation
import ScannerKit
import ScannerKitTesting
import Testing

struct TextReaderTests {
    @Test func readsTheLinesWithFramesFromTheTopLeft() async throws {
        let lines = try await TextReader().lines(in: SyntheticPage().render())
        #expect(lines.count == 30)
        let first = try #require(lines.first)
        #expect(first.text == "The quick brown fox jumps over the lazy dog")
        #expect(first.frame.minY < 0.15)
        #expect(first.frame.minX < 0.1)
    }

    @Test func failsWhenTheTextCannotBeRead() async {
        let page = SyntheticPage().render()
        await #expect(throws: (any Error).self) { try await inCancelledTask { try await TextReader().lines(in: page) } }
    }

    @Test func readsSmallPrint() async throws {
        let page = SyntheticPage().render()
        let small = page.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        let sheet = small.composited(over: CIImage(color: .white).cropped(to: page.extent))
        let lines = try await TextReader().lines(in: sheet)
        #expect(lines.contains { $0.text == "The quick brown fox jumps over the lazy dog" })
    }

    @Test(.timeLimit(.minutes(1)))
    func readsMorePagesAtOnceThanThereAreThreads() async throws {
        let page = SyntheticPage(lines: 5).render()
        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<ProcessInfo.processInfo.activeProcessorCount + 2 {
                group.addTask { try await TextReader().lines(in: page).count }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(counts.count == ProcessInfo.processInfo.activeProcessorCount + 2)
        #expect(counts.allSatisfy { $0 > 0 })
    }
}
