import Foundation
import ScannerKit

/// The Paperless tokens of the owners, kept out of the settings.
public protocol PaperlessTokens: Sendable {
    func token(for ownerID: UUID) -> String?
    /// Nil deletes the token.
    func setToken(_ token: String?, for ownerID: UUID) throws
    /// The owners that have a token.
    func ownerIDs() -> Set<UUID>
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

    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let maximumRetries = 30
    private let uploader: any Uploader
    private let tokens: any PaperlessTokens
    /// Where the request bodies wait until their upload is done.
    private let directory: URL
    /// Sends the requests that prepare an upload, while the app is open.
    private let fetch: Fetch
    /// The IDs of the objects of each catalog of each server and token by key, nil for one that cannot be sent; read once per launch and completed with the ones created.
    /// Owners with another Paperless user on the same server can see other objects.
    private var ids: [Known: [String: Int?]] = [:]
    /// The model of a scan, set by the app model.
    var model: (UUID) -> ScanModel? = { _ in nil }
    /// The scans, set by the app model.
    var scans: () -> [Scan] = { [] }
    /// Results wait while the app is not active, as scans may not be readable then; the uploads that could not be prepared are prepared again once it is.
    var isActive = true {
        didSet {
            guard isActive else { return }
            let waiting = pending
            pending = []
            waiting.forEach(complete)
            Task { await prepareWaitingUploads() }
        }
    }
    private var pending: [UploadResult] = []

    public init(uploader: any Uploader, tokens: any PaperlessTokens, directory: URL, fetch: @escaping Fetch) {
        self.uploader = uploader
        self.tokens = tokens
        self.directory = directory
        self.fetch = fetch
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

    /// Deletes the tokens no owner with a server uses, such as the ones the Keychain keeps after the app is deleted and installed again.
    func forgetTokens(keeping owners: [Owner]) {
        let kept = Set(owners.filter { $0.paperless != nil }.map(\.id))
        for id in tokens.ownerIDs().subtracting(kept) { try? tokens.setToken(nil, for: id) }
    }

    /// Throws when a scan cannot be archived: its owner has no server, or its PDF is not ready.
    public func check(_ models: [ScanModel]) throws {
        if let owner = AppModel.owners(of: models).first(where: { !isConnected($0) }) { throw ArchiveError.notConnected(owner.id) }
        guard models.allSatisfy({ if case .ready = $0.pdf { true } else { false } }) else { throw ArchiveError.noPDF }
    }

    /// Starts the upload of each checked scan, at once for a scan waiting for another try; they count as sent once the server took them.
    public func archive(_ models: [ScanModel]) async {
        for model in models {
            if model.scan.archiving?.isInProgress == true { uploader.cancel(scanID: model.id) }
            removeBody(model.id)
            model.setArchiving(Archiving())
        }
        for model in models { await prepare(model) }
    }

    /// Prepares the upload of the scans that could not be, as the server could not be reached to find their correspondent, document type or owner field.
    func prepareWaitingUploads() async {
        for scan in scans() {
            guard case .waiting = scan.archiving?.state, uploadedBody(scan.id) == nil, let model = model(scan.id) else { continue }
            await prepare(model)
        }
    }

    /// Finds or creates the correspondent of the scan's issuer, the document type of its category and the Owner custom field, then makes the PDF unless it is current, as after a relaunch, saves the request body and starts the upload.
    /// The scan waits for the app to be active again when the server cannot be reached; it goes without the ones the server refuses to make.
    private func prepare(_ model: ScanModel) async {
        let owner = model.owner
        guard let server = owner.paperless, let token = tokens.token(for: owner.id) else {
            return fail(model, "Paperless is no longer connected.")
        }
        let correspondent: Int?
        let documentType: Int?
        let ownerField: Int?
        do throws(Unreachable) {
            correspondent = try await findCorrespondent(of: model.scan.details.issuer, server: server.url, token: token).get()
            documentType = try await findDocumentType(of: model.scan.details.category, server: server.url, token: token).get()
            ownerField = try await find(Paperless.ownerField, in: .customFields, server: server.url, token: token).get()
        } catch {
            guard model.scan.archiving?.isInProgress == true else { return }
            return model.setArchiving(Archiving(state: .waiting(error.reason), retries: model.scan.archiving?.retries ?? 0))
        }
        await model.preparePDF()
        guard model.scan.archiving?.isInProgress == true, self.model(model.id) === model else { return }
        let ownerName = owner.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let customFields = if let ownerField, !ownerName.isEmpty { [ownerField: ownerName] } else { [Int: String]() }
        guard case .ready(let url, _) = model.pdf, let pdf = try? Data(contentsOf: url) else {
            return fail(model, model.pdf == .storageFull ? "The iPhone storage is full." : "The PDF could not be read. Archive the scan again.")
        }
        let boundary = "Roneograph-\(UUID().uuidString)"
        let body = Paperless.uploadBody(pdf: pdf, fileName: url.lastPathComponent, title: model.scan.title, created: model.scan.details.date, correspondent: correspondent, documentType: documentType, storagePath: server.storagePath?.id, customFields: customFields, boundary: boundary)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try body.write(to: bodyURL(model.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return fail(model, error.isStorageFull ? "The iPhone storage is full." : "The upload could not be prepared.")
        }
        if model.scan.archiving?.state != .uploading { model.setArchiving(Archiving(retries: model.scan.archiving?.retries ?? 0)) }
        start(model, boundary: boundary, after: .zero)
    }

    struct Unreachable: Error {
        let reason: String
    }

    /// The ID of the document type named like the category; nil for Other.
    private func findDocumentType(of category: DocumentCategory, server: URL, token: String) async -> Result<Int?, Unreachable> {
        guard category != .other else { return .success(nil) }
        return await find(category.rawValue, in: .documentTypes, server: server, token: token)
    }

    /// The ID of the correspondent named like the issuer; nil when the scan has none.
    private func findCorrespondent(of issuer: String?, server: URL, token: String) async -> Result<Int?, Unreachable> {
        guard let name = issuer?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return .success(nil) }
        return await find(name, in: .correspondents, server: server, token: token)
    }

    /// The ID of the object of a catalog under the key of its name, read once per launch and created when the server has none;
    /// nil when it cannot be sent, or when the server refuses to list or make it.
    private func find(_ name: String, in catalog: Catalog, server: URL, token: String) async -> Result<Int?, Unreachable> {
        let known = Known(server: server, token: token, catalog: catalog.id)
        if ids[known] == nil {
            switch await send(catalog.list(server, token)) {
            case .answered(let data, let response):
                guard let read = try? catalog.read(data, response) else { return .success(nil) }
                ids[known] = read
            case .unreachable(let reason): return .failure(Unreachable(reason: reason))
            case .refused: return .success(nil)
            }
        }
        let key = catalog.key(name)
        if let id = ids[known]?[key] { return .success(id) }
        switch await send(catalog.create(server, token, name)) {
        case .answered(let data, _):
            guard let id = try? Paperless.createdID(from: data) else { return .success(nil) }
            ids[known, default: [:]][key] = id
            return .success(id)
        case .unreachable(let reason): return .failure(Unreachable(reason: reason))
        case .refused: return .success(nil)
        }
    }

    private struct Known: Hashable {
        let server: URL
        let token: String
        let catalog: String
    }

    private enum Answer {
        case answered(Data, HTTPURLResponse)
        case unreachable(String)
        case refused
    }

    private func send(_ request: URLRequest) async -> Answer {
        let outcome: Paperless.Outcome
        do {
            let (data, answer) = try await fetch(request)
            let response = answer as? HTTPURLResponse
            outcome = Paperless.outcome(status: response?.statusCode, body: data, error: nil)
            if outcome == .delivered, let response { return .answered(data, response) }
        } catch {
            outcome = Paperless.outcome(status: nil, body: Data(), error: (error as? URLError)?.code ?? .unknown)
        }
        if case .retry(let reason) = outcome { return .unreachable(reason) }
        return .refused
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
            if let server = model.owner.paperless?.url { ids = ids.filter { $0.key.server != server } }
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

/// A kind of object Paperless-ngx finds by name: how to list them, read their IDs by key, and create one.
private struct Catalog: Sendable {
    let id: String
    let list: @Sendable (_ server: URL, _ token: String) -> URLRequest
    /// The IDs by key; nil for an object that exists but cannot be sent.
    let read: @Sendable (Data, HTTPURLResponse) throws -> [String: Int?]
    let create: @Sendable (_ server: URL, _ token: String, _ name: String) -> URLRequest
    let key: @Sendable (_ name: String) -> String

    /// Matched by lowercased name, so the ones named by hand on the server are reused whatever their case.
    static let documentTypes = Catalog(
        id: "document types",
        list: Paperless.documentTypesRequest,
        read: { data, _ in try Paperless.idsByLowercasedName(from: data) },
        create: Paperless.createDocumentTypeRequest,
        key: { $0.lowercased() }
    )

    /// Matched by lowercased name, like document types.
    static let correspondents = Catalog(
        id: "correspondents",
        list: Paperless.correspondentsRequest,
        read: { data, _ in try Paperless.idsByLowercasedName(from: data) },
        create: Paperless.createCorrespondentRequest,
        key: { $0.lowercased() }
    )

    /// Matched by exact name, as templates name them; a server too old to take custom field values with an upload cannot take the Owner field.
    static let customFields = Catalog(
        id: "custom fields",
        list: Paperless.customFieldsRequest,
        read: { data, response in
            guard Paperless.takesCustomFieldValues(version: response.value(forHTTPHeaderField: "X-Version")) else { return [Paperless.ownerField: nil] }
            return try Paperless.customFields(from: data).mapValues { $0.takesText ? $0.id : nil }
        },
        create: Paperless.createTextFieldRequest,
        key: { $0 }
    )
}
