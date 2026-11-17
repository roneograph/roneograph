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
    public func flatURL(scanID: UUID, page: ScanPage) -> URL {
        directory(of: scanID).appending(path: "\(page.id.uuidString)\(page.crop == 0 ? "" : "-\(page.crop)")-flat.jpg")
    }

    public func previewURL(scanID: UUID, pageID: UUID) -> URL { directory(of: scanID).appending(path: "\(pageID.uuidString)-preview.jpg") }

    /// The local PDF never goes into the folders of a custom format.
    public func pdfURL(of scan: Scan) -> URL {
        documentsDirectory.appending(path: "\(scan.fileName).pdf")
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

    /// All scans, newest first; unreadable folders are skipped.
    public func all() -> [Scan] {
        folders().compactMap(read).sorted { $0.created > $1.created }
    }

    /// Deletes the scan folders whose scan.json is missing, as left when the app quits before a scan is first saved, or cannot be decoded, except the kept ones.
    /// A scan.json that cannot be read for now, as while the iPhone is locked, is kept.
    public func deleteUnreadableScans(keeping kept: Set<UUID>) {
        for folder in folders() where isBroken(folder) {
            guard let id = UUID(uuidString: folder.lastPathComponent), !kept.contains(id) else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func isBroken(_ folder: URL) -> Bool {
        do {
            return decode(try Data(contentsOf: folder.appending(path: "scan.json"))) == nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return true
        } catch {
            return false
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

    /// The size of the scans and their PDFs, in bytes; reads every scan, so off the main actor.
    @concurrent
    public func byteCount() async -> Int {
        let pdfs = all().map(pdfURL)
        let files = FileManager.default.enumerator(at: scansDirectory, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL } ?? []
        return (files + pdfs).reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// A name whose PDF does not collide with the PDF of another of the scans or any other file: "Invoice", then "Invoice 2", and so on.
    /// Only the file name counts, as all local PDFs share one folder; the folders of the name are kept.
    public func availableName(_ name: String, for scan: Scan, among scans: [Scan], separator: String = " ") -> String {
        let taken = Set(scans.filter { $0.id != scan.id }.map { $0.fileName.lowercased() })
        let folders = name.split(separator: "/").dropLast().map { "\($0)/" }.joined()
        let fileName = Scan(name: name).fileName
        return folders + FileNamer.available(fileName, separator: separator) { candidate in
            taken.contains(candidate.lowercased()) || (candidate != scan.fileName && FileManager.default.fileExists(atPath: documentsDirectory.appending(path: "\(candidate).pdf").path(percentEncoded: false)))
        }
    }

    /// Moves the PDF along with a renamed scan; one that cannot be moved is deleted, as nothing would delete it under its old name.
    public func movePDF(from oldFileName: String, to scan: Scan) {
        let old = documentsDirectory.appending(path: "\(oldFileName).pdf")
        guard oldFileName != scan.fileName, FileManager.default.fileExists(atPath: old.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.moveItem(at: old, to: pdfURL(of: scan))
        } catch {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
