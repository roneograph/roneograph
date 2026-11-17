import ScannerKit
import UIKit

/// A UIKit background task, so the page or PDF being written when the app leaves the screen is finished.
struct SystemBackgroundActivity: BackgroundActivity {
    func begin() async -> @Sendable () -> Void {
        let task = await BackgroundTask()
        return { Task { @MainActor in task.end() } }
    }
}

@MainActor
private final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "Saving scans") { [weak self] in self?.end() }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
