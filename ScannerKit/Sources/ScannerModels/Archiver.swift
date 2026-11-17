import Foundation
import ScannerKit

/// The Paperless tokens of the owners, kept out of the settings.
public protocol PaperlessTokens: Sendable {
    func token(for ownerID: UUID) -> String?
    /// Nil deletes the token.
    func setToken(_ token: String?, for ownerID: UUID) throws
}

/// The answer to an upload, or the error that stopped it.
public struct UploadResult: Sendable {
    public let scanID: UUID
    public let status: Int?
    public let body: Data
    public let error: URLError.Code?

    public init(scanID: UUID, status: Int?, body: Data = Data(), error: URLError.Code? = nil) {
        self.scanID = scanID
        self.status = status
        self.body = body
        self.error = error
    }
}

/// Sends a request body saved in a file, even once the app is in the background or was stopped by the system; each result goes to `Archiver.complete(_:)`,
/// except for the uploads cancelled with `cancel(scanID:)`.
@MainActor
public protocol Uploader: AnyObject {
    func upload(_ request: URLRequest, fromFile file: URL, scanID: UUID, after delay: Duration)
    func cancel(scanID: UUID)
}

/// Sends scans to the Paperless-ngx server of their owner, and tries again later when the server cannot take them yet.
@MainActor
public final class Archiver {
    public enum ArchiveError: Error, Equatable {
        /// The owner has no server, or its token is gone.
        case notConnected(UUID)
        case noPDF
    }

    static let maximumRetries = 30
    private let uploader: any Uploader
    private let tokens: any PaperlessTokens
    /// Where the request bodies wait until their upload is done.
    private let directory: URL
    /// The model of a scan, set by the app model.
    var model: (UUID) -> ScanModel? = { _ in nil }
    /// Results wait while the app is not active, as scans may not be readable then.
    var isActive = true {
        didSet {
            guard isActive else { return }
            let waiting = pending
            pending = []
            waiting.forEach(complete)
        }
    }
    private var pending: [UploadResult] = []

    public init(uploader: any Uploader, tokens: any PaperlessTokens, directory: URL) {
        self.uploader = uploader
        self.tokens = tokens
        self.directory = directory
    }

    public func isConnected(_ owner: Owner) -> Bool {
        owner.paperless != nil && tokens.token(for: owner.id) != nil
    }

    public func token(for ownerID: UUID) -> String? {
        tokens.token(for: ownerID)
    }

    func setToken(_ token: String?, for ownerID: UUID) throws {
        try tokens.setToken(token, for: ownerID)
    }

    /// Starts the upload of each scan, at once for a scan waiting for another try; they count as sent once the server took them. Each scan needs its PDF ready.
    public func archive(_ models: [ScanModel]) throws {
        if let owner = AppModel.owners(of: models).first(where: { !isConnected($0) }) { throw ArchiveError.notConnected(owner.id) }
        guard models.allSatisfy({ if case .ready = $0.pdf { true } else { false } }) else { throw ArchiveError.noPDF }
        for model in models {
            guard case .ready(let url, _) = model.pdf, let server = model.owner.paperless else { continue }
            let pdf = try Data(contentsOf: url)
            let boundary = "Roneograph-\(UUID().uuidString)"
            let body = Paperless.uploadBody(pdf: pdf, fileName: url.lastPathComponent, title: model.scan.title, created: model.scan.details.date, storagePath: server.storagePath?.id, boundary: boundary)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if model.scan.archiving?.isInProgress == true { uploader.cancel(scanID: model.id) }
            try body.write(to: bodyURL(model.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            model.setArchiving(Archiving())
            start(model, boundary: boundary, after: .zero)
        }
    }

    /// Acts on the answer of the server: the scan is sent, waits for another try, or failed.
    /// An upload cancelled by the system, as when the app is force-quit, is tried again.
    public func complete(_ result: UploadResult) {
        guard isActive else { return pending.append(result) }
        guard let model = model(result.scanID), let archiving = model.scan.archiving, archiving.isInProgress else {
            removeBody(result.scanID)
            return
        }
        switch Paperless.outcome(status: result.status, body: result.body, error: result.error) {
        case .delivered:
            removeBody(model.id)
            model.setArchiving(nil)
            model.markSent(.paperless)
        case .retry(let reason) where archiving.retries < Self.maximumRetries:
            let retries = archiving.retries + 1
            model.setArchiving(Archiving(state: .waiting(reason), retries: retries))
            restart(model, after: Self.delay(afterRetries: retries))
        case .retry(let reason), .failed(let reason):
            fail(model, reason)
        }
    }

    /// 30 seconds, doubled after each try up to an hour, so a server down for a day is tried about 30 times.
    static func delay(afterRetries retries: Int) -> Duration {
        .seconds(min(30 * (1 << min(retries - 1, 7)), 3600))
    }

    /// Stops the upload of a deleted scan.
    func cancel(_ scanID: UUID) {
        uploader.cancel(scanID: scanID)
        removeBody(scanID)
    }

    /// Sends the body saved on the first try again, with the current token of the owner.
    private func restart(_ model: ScanModel, after delay: Duration) {
        guard let body = uploadedBody(model.id), let boundary = Self.boundary(of: body) else {
            fail(model, "The upload was interrupted. Archive the scan again.")
            return
        }
        guard isConnected(model.owner) else {
            fail(model, "Paperless is no longer connected.")
            return
        }
        start(model, boundary: boundary, after: delay)
    }

    private func start(_ model: ScanModel, boundary: String, after delay: Duration) {
        guard let server = model.owner.paperless, let token = tokens.token(for: model.owner.id) else { return }
        uploader.upload(Paperless.uploadRequest(server: server.url, token: token, boundary: boundary), fromFile: bodyURL(model.id), scanID: model.id, after: delay)
    }

    private func fail(_ model: ScanModel, _ reason: String) {
        removeBody(model.id)
        model.setArchiving(Archiving(state: .failed(reason), retries: model.scan.archiving?.retries ?? 0))
    }

    /// The boundary is the first line of the body, after its two dashes.
    private static func boundary(of body: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: body) else { return nil }
        defer { try? handle.close() }
        let start = (try? handle.read(upToCount: 200)) ?? Data()
        guard let line = String(decoding: start, as: UTF8.self).split(separator: "\r\n").first, line.hasPrefix("--") else { return nil }
        return String(line.dropFirst(2))
    }

    private func bodyURL(_ scanID: UUID) -> URL {
        directory.appending(path: "\(scanID.uuidString).form")
    }

    private func uploadedBody(_ scanID: UUID) -> URL? {
        let url = bodyURL(scanID)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    private func removeBody(_ scanID: UUID) {
        try? FileManager.default.removeItem(at: bodyURL(scanID))
    }
}
