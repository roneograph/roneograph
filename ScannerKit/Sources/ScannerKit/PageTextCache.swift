import Foundation
import Synchronization

/// The text read on each page revision, so renaming a scan does not read all its pages again.
public final class PageTextCache: Sendable {
    private struct Key: Hashable {
        let page: UUID
        let revision: Int
    }

    private let lines = Mutex<[Key: [TextLine]]>([:])

    public init() {}

    public func lines(of page: ScanPage, read: () -> [TextLine]) -> [TextLine] {
        let key = Key(page: page.id, revision: page.revision)
        if let cached = lines.withLock({ $0[key] }) { return cached }
        let read = read()
        lines.withLock { $0[key] = read }
        return read
    }
}
