import Foundation

/// Keeps each scan in its own hidden folder (photos, flattened pages, previews, scan.json),
/// and its PDF in the documents folder, which the Files app shows.
public struct ScanStore: Sendable {
    public let scansDirectory: URL
    public let documentsDirectory: URL

    public init(scansDirectory: URL, documentsDirectory: URL) {
        self.scansDirectory = scansDirectory
        self.documentsDirectory = documentsDirectory
    }

    public func directory(of scanID: UUID) -> URL {
        scansDirectory.appending(path: scanID.uuidString, directoryHint: .isDirectory)
    }

    public func photoURL(scanID: UUID, pageID: UUID) -> URL { directory(of: scanID).appending(path: "\(pageID.uuidString)-photo.jpg") }
    public func flatURL(scanID: UUID, pageID: UUID) -> URL { directory(of: scanID).appending(path: "\(pageID.uuidString)-flat.jpg") }
    public func previewURL(scanID: UUID, pageID: UUID) -> URL { directory(of: scanID).appending(path: "\(pageID.uuidString)-preview.jpg") }

    public func pdfURL(of scan: Scan) -> URL {
        documentsDirectory.appending(path: "\(scan.name).pdf")
    }

    public func save(_ scan: Scan) throws {
        try FileManager.default.createDirectory(at: directory(of: scan.id), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(scan).write(to: directory(of: scan.id).appending(path: "scan.json"), options: .atomic)
    }

    /// All scans, newest first; unreadable folders are skipped.
    public func all() -> [Scan] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let folders = (try? FileManager.default.contentsOfDirectory(at: scansDirectory, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            (try? Data(contentsOf: folder.appending(path: "scan.json"))).flatMap { try? decoder.decode(Scan.self, from: $0) }
        }.sorted { $0.created > $1.created }
    }

    public func delete(_ scan: Scan) {
        try? FileManager.default.removeItem(at: directory(of: scan.id))
        try? FileManager.default.removeItem(at: pdfURL(of: scan))
    }

    public func deletePageFiles(scanID: UUID, pageID: UUID) {
        for url in [photoURL(scanID: scanID, pageID: pageID), flatURL(scanID: scanID, pageID: pageID), previewURL(scanID: scanID, pageID: pageID)] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes the scans created before the cutoff, with their PDF.
    public func deleteScans(olderThan cutoff: Date) {
        for scan in all() where scan.created < cutoff {
            delete(scan)
        }
    }

    /// A name whose PDF does not collide with another scan's PDF or any other file: "Invoice", then "Invoice 2", and so on.
    public func availableName(_ name: String, for scan: Scan, separator: String = " ") -> String {
        let taken = Set(all().filter { $0.id != scan.id }.map { $0.name.lowercased() })
        var candidate = name
        var counter = 2
        while taken.contains(candidate.lowercased()) || (candidate != scan.name && FileManager.default.fileExists(atPath: documentsDirectory.appending(path: "\(candidate).pdf").path(percentEncoded: false))) {
            candidate = "\(name)\(separator)\(counter)"
            counter += 1
        }
        return candidate
    }

    /// Moves the PDF along with a renamed scan.
    public func movePDF(from oldName: String, to scan: Scan) {
        let old = documentsDirectory.appending(path: "\(oldName).pdf")
        guard oldName != scan.name, FileManager.default.fileExists(atPath: old.path(percentEncoded: false)) else { return }
        try? FileManager.default.removeItem(at: pdfURL(of: scan))
        try? FileManager.default.moveItem(at: old, to: pdfURL(of: scan))
    }
}
