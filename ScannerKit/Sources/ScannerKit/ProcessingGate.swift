import Synchronization

/// Runs one piece of page work at a time across all scans, in the order asked, so Core Image and Vision never render two pages at once:
/// rendering pages concurrently on one context changes their pixels, and multiplies the memory used.
public final class ProcessingGate: Sendable {
    private struct State {
        var isBusy = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    public init() {}

    /// The work waiting for its turn.
    var waitingCount: Int { state.withLock(\.waiting.count) }

    /// Waits for the work before to finish, then runs `work`; never call it from inside `work`.
    public func run<T>(isolation: isolated (any Actor)? = #isolation, _ work: () async throws -> T) async rethrows -> T {
        await enter()
        defer { leave() }
        return try await work()
    }

    private func enter() async {
        await withCheckedContinuation { continuation in
            let entered = state.withLock { state in
                guard state.isBusy else {
                    state.isBusy = true
                    return true
                }
                state.waiting.append(continuation)
                return false
            }
            if entered { continuation.resume() }
        }
    }

    private func leave() {
        let next = state.withLock { state in
            guard !state.waiting.isEmpty else {
                state.isBusy = false
                return nil as CheckedContinuation<Void, Never>?
            }
            return state.waiting.removeFirst()
        }
        next?.resume()
    }
}
