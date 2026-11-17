import ScannerKit
import Synchronization

/// Counts the requests to keep the app running in the background.
public final class RecordingBackground: BackgroundActivity {
    private let state = Mutex((begun: 0, running: 0))

    public init() {}

    public var begun: Int { state.withLock(\.begun) }
    public var running: Int { state.withLock(\.running) }

    public func begin() async -> @Sendable () -> Void {
        state.withLock {
            $0.begun += 1
            $0.running += 1
        }
        return { self.state.withLock { $0.running -= 1 } }
    }
}
