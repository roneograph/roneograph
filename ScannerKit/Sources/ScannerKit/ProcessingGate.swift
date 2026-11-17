import Synchronization

/// Keeps the app running in the background, so that work it started, such as writing a file, is not cut off.
public protocol BackgroundActivity: Sendable {
    /// Asks to keep running until the returned closure is called.
    func begin() async -> @Sendable () -> Void
}

/// Runs one piece of page work at a time across all scans, in the order asked, so Core Image and Vision never render two pages at once:
/// rendering pages concurrently on one context changes their pixels, and multiplies the memory used.
/// While paused, as when the app is in the background where the GPU cannot be used, no work starts; work already started finishes.
public final class ProcessingGate: Sendable {
    private struct State {
        var isBusy = false
        var isPaused = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    private let background: (any BackgroundActivity)?

    public init(background: (any BackgroundActivity)? = nil) {
        self.background = background
    }

    /// The work waiting for its turn.
    var waitingCount: Int { state.withLock(\.waiting.count) }

    public var isPaused: Bool {
        get { state.withLock(\.isPaused) }
        set {
            let next = state.withLock { state in
                state.isPaused = newValue
                guard !newValue, !state.isBusy, !state.waiting.isEmpty else { return nil as CheckedContinuation<Void, Never>? }
                state.isBusy = true
                return state.waiting.removeFirst()
            }
            next?.resume()
        }
    }

    /// Waits for the work before to finish and for the gate to be open, then runs `work`, keeping the app running until it is done; never call it from inside `work`.
    public func run<T>(isolation: isolated (any Actor)? = #isolation, _ work: () async throws -> T) async rethrows -> T {
        await enter()
        defer { leave() }
        return try await finish(work)
    }

    /// Runs `work` right away, keeping the app running until it is done, as for writing a file.
    public func finish<T>(isolation: isolated (any Actor)? = #isolation, _ work: () async throws -> T) async rethrows -> T {
        let end = await background?.begin()
        defer { end?() }
        return try await work()
    }

    private func enter() async {
        await withCheckedContinuation { continuation in
            let entered = state.withLock { state in
                guard state.isBusy || state.isPaused else {
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
            guard !state.isPaused, !state.waiting.isEmpty else {
                state.isBusy = false
                return nil as CheckedContinuation<Void, Never>?
            }
            return state.waiting.removeFirst()
        }
        next?.resume()
    }
}
