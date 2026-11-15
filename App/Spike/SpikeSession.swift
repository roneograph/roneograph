import CoreImage
import Foundation
import Observation
import ScannerKit
import UIKit

/// What happened to one captured page, saved next to its images for the comparison report.
struct PageMetadata: Codable, Sendable {
    var number: Int
    var automatic: Bool
    var liveDetection: PageDetection?
    var stillDetection: PageDetection?
    var photoWidth: Int
    var photoHeight: Int
    var pageWidth: Int
    var pageHeight: Int
    var captureLatency: TimeInterval
    var processingDuration: TimeInterval
}

struct SpikePage: Identifiable, Sendable {
    let metadata: PageMetadata
    let photoURL: URL
    let pageURL: URL
    var id: Int { metadata.number }

    var usedQuad: Quad? { metadata.stillDetection?.quad ?? metadata.liveDetection?.quad }
}

struct LiveStats: Codable, Sendable {
    var frames = 0
    var framesWithPage = 0
    var totalDetectionDuration: TimeInterval = 0

    var averageDetectionMilliseconds: Double {
        frames == 0 ? 0 : totalDetectionDuration / Double(frames) * 1000
    }
}

/// One comparison session: our pages and Apple's, saved under Documents/Spike/<date>/ to be pulled to a Mac.
@MainActor @Observable
final class SpikeSession {
    private(set) var directory: URL
    private(set) var pages: [SpikePage] = []
    private(set) var applePages: [URL] = []
    var liveStats = LiveStats()

    init() {
        directory = Self.newDirectory()
    }

    func reset() {
        directory = Self.newDirectory()
        pages = []
        applePages = []
        liveStats = LiveStats()
    }

    var nextNumber: Int { pages.count + 1 }

    func add(_ page: SpikePage) {
        pages.append(page)
        saveStats()
    }

    func addApplePages(_ images: [UIImage]) {
        let start = applePages.count
        for (offset, image) in images.enumerated() {
            let url = directory.appending(path: String(format: "apple-%02d.jpg", start + offset + 1))
            if let data = image.jpegData(compressionQuality: 0.85), (try? data.write(to: url)) != nil {
                applePages.append(url)
            }
        }
    }

    func applePage(for page: SpikePage) -> URL? {
        applePages.indices.contains(page.metadata.number - 1) ? applePages[page.metadata.number - 1] : nil
    }

    private func saveStats() {
        struct Stats: Encodable {
            let device: String
            let system: String
            let live: LiveStats
            let averageDetectionMilliseconds: Double
        }
        let stats = Stats(device: Self.deviceModel, system: UIDevice.current.systemVersion, live: liveStats, averageDetectionMilliseconds: liveStats.averageDetectionMilliseconds)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(stats).write(to: directory.appending(path: "session.json"))
    }

    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    private static func newDirectory() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = URL.documentsDirectory.appending(path: "Spike/\(formatter.string(from: .now))")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Turns a captured photo into a flat page: detects the page again on the full photo, removes the perspective, saves both.
struct PageProcessor: Sendable {
    let extractor: PageExtractor

    func process(_ photo: CapturedPhoto, number: Int, automatic: Bool, liveDetection: PageDetection?, directory: URL) throws -> SpikePage {
        let started = CFAbsoluteTimeGetCurrent()
        guard let image = CIImage(data: photo.data, options: [.applyOrientationProperty: true]) else { throw CameraError.noPhotoData }

        let longSide = max(image.extent.width, image.extent.height)
        let scale = min(1, 1600 / longSide)
        let stillDetection = extractor.detect(in: image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        let quad = stillDetection?.quad ?? liveDetection?.quad
        let page = quad.map { extractor.correct(image, quad: $0) } ?? image
        guard let pageData = extractor.jpegData(of: page, quality: 0.85) else { throw CameraError.noPhotoData }

        let name = String(format: "ours-%02d", number)
        let photoURL = directory.appending(path: "\(name)-photo.jpg")
        let pageURL = directory.appending(path: "\(name)-page.jpg")
        try photo.data.write(to: photoURL)
        try pageData.write(to: pageURL)

        let metadata = PageMetadata(
            number: number, automatic: automatic, liveDetection: liveDetection, stillDetection: stillDetection,
            photoWidth: Int(image.extent.width), photoHeight: Int(image.extent.height),
            pageWidth: Int(page.extent.width), pageHeight: Int(page.extent.height),
            captureLatency: photo.latency, processingDuration: CFAbsoluteTimeGetCurrent() - started
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: directory.appending(path: "\(name).json"))
        return SpikePage(metadata: metadata, photoURL: photoURL, pageURL: pageURL)
    }
}
