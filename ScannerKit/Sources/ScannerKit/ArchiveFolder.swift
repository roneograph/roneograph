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
                let destination = Self.availableURL(in: folder, name: name, separator: separator)
                try FileManager.default.copyItem(at: file, to: destination)
                return destination
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private static func availableURL(in folder: URL, name: String, separator: String) -> URL {
        var url = folder.appending(path: "\(name).pdf")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = folder.appending(path: "\(name)\(separator)\(number).pdf")
            number += 1
        }
        return url
    }
}
