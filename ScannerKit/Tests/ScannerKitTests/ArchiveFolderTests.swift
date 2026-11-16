import Foundation
import ScannerKit
import Testing

final class ArchiveFolderTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ArchiveFolderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    lazy var folder = root.appending(path: "Paperwork", directoryHint: .isDirectory)
    lazy var pdf = root.appending(path: "scan.pdf")

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("%PDF".utf8).write(to: pdf)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func remembersTheFolderByName() throws {
        #expect(try ArchiveFolder(url: folder).name == "Paperwork")
    }

    @Test func savesWithoutReplacingAFileAlreadyThere() throws {
        var archive = try ArchiveFolder(url: folder)
        let first = try archive.save(pdf, as: "Invoice", separator: "-")
        let second = try archive.save(pdf, as: "Invoice", separator: "-")
        #expect(first.lastPathComponent == "Invoice.pdf")
        #expect(second.lastPathComponent == "Invoice-2.pdf")
        #expect(try Data(contentsOf: folder.appending(path: "Invoice-2.pdf")) == Data("%PDF".utf8))
    }

    @Test func failsWhenTheFolderIsGone() throws {
        var archive = try ArchiveFolder(url: folder)
        try FileManager.default.removeItem(at: folder)
        #expect(throws: (any Error).self) { try archive.save(pdf, as: "Invoice") }
    }
}
