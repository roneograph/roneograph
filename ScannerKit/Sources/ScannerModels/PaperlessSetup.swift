import Foundation
import Observation
import ScannerKit

/// Connects an owner to a Paperless-ngx server: checks the address and token by listing the storage paths, then keeps the one picked.
@MainActor @Observable
public final class PaperlessSetup {
    public enum State: Equatable {
        case idle, connecting
        case connected([PaperlessStoragePath])
        case failed(String)
    }

    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public var address: String {
        didSet { if address != oldValue { state = .idle } }
    }
    public var token: String {
        didSet { if token != oldValue { state = .idle } }
    }
    public var storagePath: PaperlessStoragePath?
    public private(set) var state = State.idle
    public let ownerID: UUID
    private let settings: SettingsStore
    private let archiver: Archiver
    private let fetch: Fetch
    /// The address and token the storage paths were listed with.
    private var connected: (server: URL, token: String)?

    /// Starts from the owner's server, or from another owner's, as several owners often share one server.
    public init(ownerID: UUID, settings: SettingsStore, archiver: Archiver, fetch: @escaping Fetch) {
        self.ownerID = ownerID
        self.settings = settings
        self.archiver = archiver
        self.fetch = fetch
        let owner = settings.value.owner(ownerID)
        let source = owner.paperless != nil ? owner : settings.value.owners.first { $0.paperless != nil && archiver.token(for: $0.id) != nil }
        address = source?.paperless?.url.absoluteString ?? ""
        token = source.flatMap { archiver.token(for: $0.id) } ?? ""
        storagePath = owner.paperless?.storagePath
    }

    public var isConnected: Bool {
        if case .connected = state { true } else { false }
    }

    /// Whether saving would change the owner's server, token or storage path.
    public var hasChanges: Bool {
        guard isConnected, let connected else { return false }
        return settings.value.owner(ownerID).paperless != PaperlessServer(url: connected.server, storagePath: storagePath)
            || archiver.token(for: ownerID) != connected.token
    }

    /// Lists the storage paths right away for an owner already connected, so they can be changed without connecting again.
    public func connectToSavedServer() async {
        guard state == .idle, archiver.isConnected(settings.value.owner(ownerID)) else { return }
        await connect()
    }

    public func connect() async {
        guard let server = Paperless.serverURL(from: address) else {
            state = .failed("Type the address of the server, such as https://paperless.example.com.")
            return
        }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            state = .failed("Paste the API token of your Paperless user.")
            return
        }
        state = .connecting
        let typed = (address: address, token: self.token)
        let data: Data, status: Int?
        do {
            let response: URLResponse
            (data, response) = try await fetch(Paperless.storagePathsRequest(server: server, token: token))
            status = (response as? HTTPURLResponse)?.statusCode
        } catch {
            guard typed == (address, self.token) else { return }
            state = .failed(Self.reason(Paperless.outcome(status: nil, body: Data(), error: (error as? URLError)?.code ?? .unknown)))
            return
        }
        guard typed == (address, self.token) else { return }
        let outcome = Paperless.outcome(status: status, body: data, error: nil)
        guard outcome == .delivered, let paths = try? Paperless.storagePaths(from: data) else {
            state = .failed(Self.reason(outcome))
            return
        }
        connected = (server, token)
        storagePath = storagePath.flatMap { current in paths.first { $0.id == current.id } }
        state = .connected(paths)
    }

    private static func reason(_ outcome: Paperless.Outcome) -> String {
        switch outcome {
        case .retry(let reason), .failed(let reason): reason
        case .delivered: "The server did not answer like a Paperless-ngx server."
        }
    }

    /// Keeps the server, the token and the storage path once connected.
    public func save() throws {
        guard isConnected, let connected else { return }
        try archiver.setToken(connected.token, for: ownerID)
        var owner = settings.value.owner(ownerID)
        owner.paperless = PaperlessServer(url: connected.server, storagePath: storagePath)
        settings.value.updateOwner(owner)
    }

    /// Forgets the owner's server and token; its scans are no longer archived.
    public static func disconnect(_ ownerID: UUID, settings: SettingsStore, archiver: Archiver) {
        try? archiver.setToken(nil, for: ownerID)
        var owner = settings.value.owner(ownerID)
        owner.paperless = nil
        settings.value.updateOwner(owner)
    }
}
