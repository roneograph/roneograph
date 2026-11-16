import Foundation

/// A folder picked once in Files, kept as a bookmark so that saving to it needs no picker.
public struct ArchiveFolder: Equatable, Sendable, Codable {
    public private(set) var bookmark: Data
    public private(set) var name: String

    public enum SaveError: Error {
        case unavailable
    }

    /// Call with the URL the folder picker returned, while it is still accessible.
    public init(url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        bookmark = try url.bookmarkData()
        name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
    }

    /// Copies the file into the folder without replacing anything there: a taken name gets a number.
    /// The folders of a name such as "Invoice/2026 Lumen" are created inside the folder when missing; nothing is ever written outside it.
    /// Refreshes the bookmark when the system says it is stale, so callers should store the folder again.
    @discardableResult
    public mutating func save(_ file: URL, as name: String, separator: String = " ") throws -> URL {
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else { throw SaveError.unavailable }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        if stale, let fresh = try? folder.bookmarkData() { bookmark = fresh }

        var coordinationError: NSError?
        var result: Result<URL, Error> = .failure(SaveError.unavailable)
        NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordinationError) { folder in
            result = Result {
                var components = name.split(separator: "/").map { FileNamer.finalName(String($0), fallback: "") }.filter { !$0.isEmpty && $0 != "." && $0 != ".." }
                guard let fileName = components.popLast() else { throw SaveError.unavailable }
                let directory = components.reduce(folder) { $0.appending(path: $1, directoryHint: .isDirectory) }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = Self.availableURL(in: directory, name: fileName, separator: separator)
                try FileManager.default.copyItem(at: file, to: destination)
                return destination
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private static func availableURL(in folder: URL, name: String, separator: String) -> URL {
        let url = { (name: String) in folder.appending(path: "\(name).pdf") }
        return url(FileNamer.available(name, separator: separator) { FileManager.default.fileExists(atPath: url($0).path(percentEncoded: false)) })
    }
}
