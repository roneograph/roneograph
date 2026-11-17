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

    /// The local PDF never goes into the folders of a custom format.
    public func pdfURL(of scan: Scan) -> URL {
        documentsDirectory.appending(path: "\(scan.fileName).pdf")
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

    /// The size of the scans and their PDFs, in bytes.
    public func byteCount() -> Int {
        let pdfs = all().map(pdfURL)
        let files = FileManager.default.enumerator(at: scansDirectory, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL } ?? []
        return (files + pdfs).reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// A name whose PDF does not collide with another scan's PDF or any other file: "Invoice", then "Invoice 2", and so on.
    /// Only the file name counts, as all local PDFs share one folder; the folders of the name are kept.
    public func availableName(_ name: String, for scan: Scan, separator: String = " ") -> String {
        let taken = Set(all().filter { $0.id != scan.id }.map { $0.fileName.lowercased() })
        let folders = name.split(separator: "/").dropLast().map { "\($0)/" }.joined()
        let fileName = Scan(name: name).fileName
        return folders + FileNamer.available(fileName, separator: separator) { candidate in
            taken.contains(candidate.lowercased()) || (candidate != scan.fileName && FileManager.default.fileExists(atPath: documentsDirectory.appending(path: "\(candidate).pdf").path(percentEncoded: false)))
        }
    }

    /// Moves the PDF along with a renamed scan.
    public func movePDF(from oldFileName: String, to scan: Scan) {
        let old = documentsDirectory.appending(path: "\(oldFileName).pdf")
        guard oldFileName != scan.fileName, FileManager.default.fileExists(atPath: old.path(percentEncoded: false)) else { return }
        try? FileManager.default.removeItem(at: pdfURL(of: scan))
        try? FileManager.default.moveItem(at: old, to: pdfURL(of: scan))
    }
}
