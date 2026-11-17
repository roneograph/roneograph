import ScannerKit
import Synchronization

/// Counts the requests to keep the app running in the background.
public final class RecordingBackground: BackgroundActivity {
    private struct Hold: Sendable {
        let didStart: AsyncStream<Void>.Continuation
        let released: AsyncStream<Void>
    }

    private let state = Mutex((begun: 0, running: 0))
    private let hold = Mutex<Hold?>(nil)

    public init() {}

    public var begun: Int { state.withLock(\.begun) }
    public var running: Int { state.withLock(\.running) }

    /// Makes the next request wait until the returned closure is called; the stream ends once it waits.
    public func holdNext() -> (started: AsyncStream<Void>, release: @Sendable () -> Void) {
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        hold.withLock { $0 = Hold(didStart: didStart, released: released) }
        return (started, { release.finish() })
    }

    public func begin() async -> @Sendable () -> Void {
        if let held = hold.withLock({ hold in defer { hold = nil }; return hold }) {
            held.didStart.finish()
            for await _ in held.released {}
        }
        state.withLock {
            $0.begun += 1
            $0.running += 1
        }
        return { self.state.withLock { $0.running -= 1 } }
    }
}
