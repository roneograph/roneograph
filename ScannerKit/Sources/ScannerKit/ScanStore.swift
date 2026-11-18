import Foundation

/// Keeps each scan in its own hidden folder (photos, flattened pages, previews, the text read on the pages, scan.json),
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
    public func flatURL(scanID: UUID, page: ScanPage) -> URL {
        directory(of: scanID).appending(path: "\(page.id.uuidString)\(page.crop == 0 ? "" : "-\(page.crop)")-flat.jpg")
    }

    public func previewURL(scanID: UUID, pageID: UUID) -> URL { directory(of: scanID).appending(path: "\(pageID.uuidString)-preview.jpg") }
    public func textURL(scanID: UUID, pageID: UUID) -> URL { directory(of: scanID).appending(path: "\(pageID.uuidString)-text.json") }

    public func pdfURL(of scan: Scan) -> URL {
        documentsDirectory.appending(path: "\(scan.name).pdf")
    }

    public func savePhoto(_ data: Data, scanID: UUID, pageID: UUID) throws {
        try FileManager.default.createDirectory(at: directory(of: scanID), withIntermediateDirectories: true)
        try data.write(to: photoURL(scanID: scanID, pageID: pageID), options: .atomic)
    }

    public func save(_ scan: Scan) throws {
        try FileManager.default.createDirectory(at: directory(of: scan.id), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(scan).write(to: directory(of: scan.id).appending(path: "scan.json"), options: .atomic)
    }

    /// The text read on the page as it is cut and turned now, nil until it is read; a new look moves no text.
    public func text(of page: ScanPage, scanID: UUID) -> [TextLine]? {
        guard let data = try? Data(contentsOf: textURL(scanID: scanID, pageID: page.id)),
              let text = try? JSONDecoder().decode(PageText.self, from: data),
              text.crop == page.crop, text.orientation == page.analysis.orientation else { return nil }
        return text.lines
    }

    public func saveText(_ lines: [TextLine], of page: ScanPage, scanID: UUID) throws {
        try JSONEncoder().encode(PageText(crop: page.crop, orientation: page.analysis.orientation, lines: lines)).write(to: textURL(scanID: scanID, pageID: page.id), options: .atomic)
    }

    /// All scans, newest first; unreadable folders are skipped.
    public func all() -> [Scan] {
        folders().compactMap(read).sorted { $0.created > $1.created }
    }

    /// Deletes the scan folders without a scan.json, as left when the app quits before a scan is first saved, except the kept ones.
    /// A scan.json that cannot be decoded, as one written by another version of the app, or read for now, as while the iPhone is locked, is kept.
    public func deleteUnsavedScans(keeping kept: Set<UUID>) {
        for folder in folders() where !FileManager.default.fileExists(atPath: folder.appending(path: "scan.json").path(percentEncoded: false)) {
            guard let id = UUID(uuidString: folder.lastPathComponent), !kept.contains(id) else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func folders() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: scansDirectory, includingPropertiesForKeys: nil)) ?? []
    }

    private func read(_ folder: URL) -> Scan? {
        (try? Data(contentsOf: folder.appending(path: "scan.json"))).flatMap(decode)
    }

    private func decode(_ data: Data) -> Scan? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Scan.self, from: data)
    }

    public func delete(_ scan: Scan) {
        try? FileManager.default.removeItem(at: directory(of: scan.id))
        try? FileManager.default.removeItem(at: pdfURL(of: scan))
    }

    /// Deletes every file of the page, a flat page left by an interrupted recrop too.
    public func deletePageFiles(scanID: UUID, pageID: UUID) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory(of: scanID), includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(pageID.uuidString) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// A name whose PDF does not collide with the PDF of another of the scans or any other file: "Invoice", then "Invoice 2", and so on.
    public func availableName(_ name: String, for scan: Scan, among scans: [Scan], separator: String = " ") -> String {
        let taken = Set(scans.filter { $0.id != scan.id }.map { $0.name.lowercased() })
        return FileNamer.available(name, separator: separator) { candidate in
            taken.contains(candidate.lowercased()) || (candidate != scan.name && FileManager.default.fileExists(atPath: documentsDirectory.appending(path: "\(candidate).pdf").path(percentEncoded: false)))
        }
    }

    /// Moves the PDF along with a renamed scan; one that cannot be moved is deleted, as nothing would delete it under its old name.
    public func movePDF(from oldFileName: String, to scan: Scan) {
        let old = documentsDirectory.appending(path: "\(oldFileName).pdf")
        guard oldFileName != scan.name, FileManager.default.fileExists(atPath: old.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.moveItem(at: old, to: pdfURL(of: scan))
        } catch {
            try? FileManager.default.removeItem(at: old)
        }
    }
}

/// The lines read on a page, with the crop and the orientation they were read on.
private struct PageText: Codable {
    var crop: Int
    var orientation: PageOrientation
    var lines: [TextLine]
}
