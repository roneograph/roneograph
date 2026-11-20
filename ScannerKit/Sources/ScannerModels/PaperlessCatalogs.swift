import Foundation
import Observation
import ScannerKit

/// What a Paperless-ngx server answered to a request made while the app is open.
enum PaperlessAnswer {
    case answered(Data, HTTPURLResponse)
    /// Worth trying again later, for this reason.
    case unreachable(String)
    case refused

    static func to(_ request: URLRequest, fetch: Archiver.Fetch) async -> Self {
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
}

/// The correspondents and document types of each owner's Paperless-ngx server, read ahead of the uploads so Review offers them and tells what archiving would add.
/// They are saved, to be shown offline; uploads only trust the ones read since launch, as the server may have changed meanwhile.
@MainActor @Observable
public final class PaperlessCatalogs {
    enum Reading: Equatable, Sendable {
        case read
        /// Worth trying again later, for this reason.
        case unreachable(String)
        case refused
    }

    struct Key: Hashable, Codable {
        let owner: UUID
        let kind: PaperlessObjectKind
    }

    struct Catalog: Codable, Equatable {
        var server: URL
        var objects: [PaperlessObject]
        var date: Date
    }

    private struct Saved: Codable {
        var key: Key
        var catalog: Catalog
    }

    /// A server lists a few hundred objects at most on one page; this bounds a server that never ends its list.
    static let maximumPages = 50

    private var catalogs: [Key: Catalog] = [:]
    @ObservationIgnored private var matchers: [Key: PaperlessMatcher] = [:]
    /// The catalogs read since launch, which uploads trust.
    @ObservationIgnored private var current: Set<Key> = []
    @ObservationIgnored private var readings: [Key: Task<Reading, Never>] = [:]
    private let fetch: Archiver.Fetch
    private let file: URL?
    private let now: @Sendable () -> Date

    /// Without a file, the catalogs are not saved.
    init(fetch: @escaping Archiver.Fetch, file: URL?, now: @escaping @Sendable () -> Date = Date.init) {
        self.fetch = fetch
        self.file = file
        self.now = now
        guard let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Saved].self, from: data) else { return }
        for entry in saved { set(entry.catalog, for: entry.key) }
    }

    /// The objects of the owner's server, read now or on a past launch; nil until they are read once from its current server.
    public func matcher(_ kind: PaperlessObjectKind, of owner: Owner) -> PaperlessMatcher? {
        let key = Key(owner: owner.id, kind: kind)
        guard let server = owner.paperless?.url, catalogs[key]?.server == server else { return nil }
        return matchers[key]
    }

    /// Reads the objects of the owner's server, unless they were read since launch less than `maximumAge` ago, or at all when it is nil.
    /// A reading in progress is waited for rather than started again.
    func read(_ kind: PaperlessObjectKind, of owner: Owner, token: String, unlessReadWithin maximumAge: TimeInterval? = nil) async -> Reading {
        let key = Key(owner: owner.id, kind: kind)
        guard let server = owner.paperless?.url else { return .refused }
        if let reading = readings[key] { return await reading.value }
        if current.contains(key), let catalog = catalogs[key], catalog.server == server, maximumAge.map({ now().timeIntervalSince(catalog.date) < $0 }) ?? true {
            return .read
        }
        let reading = Task { await readAll(kind, of: owner.id, server: server, token: token) }
        readings[key] = reading
        let result = await reading.value
        readings[key] = nil
        return result
    }

    private func readAll(_ kind: PaperlessObjectKind, of ownerID: UUID, server: URL, token: String) async -> Reading {
        var request = Paperless.listRequest(of: kind, server: server, token: token)
        var objects: [PaperlessObject] = []
        for _ in 0..<Self.maximumPages {
            switch await PaperlessAnswer.to(request, fetch: fetch) {
            case .answered(let data, _):
                guard let page = try? Paperless.objects(from: data) else { return .refused }
                objects += page.objects
                if let next = page.next.flatMap({ Paperless.nextPageRequest(after: request, next: $0) }) {
                    request = next
                    continue
                }
                let key = Key(owner: ownerID, kind: kind)
                set(Catalog(server: server, objects: objects, date: now()), for: key)
                current.insert(key)
                save()
                return .read
            case .unreachable(let reason): return .unreachable(reason)
            case .refused: return .refused
            }
        }
        return .refused
    }

    /// Adds an object the app created on the owner's server.
    func add(_ object: PaperlessObject, _ kind: PaperlessObjectKind, of owner: Owner) {
        let key = Key(owner: owner.id, kind: kind)
        guard var catalog = catalogs[key], catalog.server == owner.paperless?.url, !catalog.objects.contains(object) else { return }
        catalog.objects.append(object)
        set(catalog, for: key)
        save()
    }

    /// The next upload to the server reads its objects again, as after a failed upload.
    func distrust(_ server: URL) {
        current = current.filter { catalogs[$0]?.server != server }
    }

    /// The next upload of the owner reads its objects again, as after the token changed.
    func distrust(ownerID: UUID) {
        current = current.filter { $0.owner != ownerID }
    }

    /// Forgets the objects of the owners not kept, as once they are disconnected.
    func keep(_ ownerIDs: Set<UUID>) {
        let forgotten = catalogs.keys.filter { !ownerIDs.contains($0.owner) }
        guard !forgotten.isEmpty else { return }
        for key in forgotten {
            catalogs[key] = nil
            matchers[key] = nil
            current.remove(key)
        }
        save()
    }

    private func set(_ catalog: Catalog, for key: Key) {
        catalogs[key] = catalog
        matchers[key] = PaperlessMatcher(catalog.objects)
    }

    /// Readable while the iPhone is locked, as uploads can be prepared then.
    private func save() {
        guard let file else { return }
        let saved = catalogs.map { Saved(key: $0.key, catalog: $0.value) }.sorted { ($0.key.owner.uuidString, $0.key.kind.rawValue) < ($1.key.owner.uuidString, $1.key.kind.rawValue) }
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
