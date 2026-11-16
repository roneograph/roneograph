import Foundation
import Synchronization

/// The text read on the latest revision of each page, so renaming a scan does not read all its pages again.
public final class PageTextCache: Sendable {
    private let lines = Mutex<[UUID: (revision: Int, lines: [TextLine])]>([:])

    public init() {}

    public func lines(of page: ScanPage, read: () async -> [TextLine]) async -> [TextLine] {
        if let cached = lines.withLock({ $0[page.id] }), cached.revision == page.revision { return cached.lines }
        let read = await read()
        lines.withLock { $0[page.id] = (page.revision, read) }
        return read
    }
}
