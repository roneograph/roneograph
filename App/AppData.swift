import Foundation
import ScannerKit

/// Where the app keeps its settings, scans, PDFs and Paperless tokens; UI tests get fresh ones, apart from the app's own data.
struct AppData {
    var support = URL.applicationSupportDirectory
    var documents = URL.documentsDirectory
    var defaults = UserDefaults.standard
    var paperlessIdentifier = "org.roneograph.app.paperless"
    /// The settings to start from instead of the saved ones.
    var settings: ScannerSettings?

    static var current: AppData {
        #if DEBUG
        if ProcessInfo.processInfo.environment["RONEOGRAPH_UI_TESTING"] != nil { return uiTesting() }
        #endif
        return AppData()
    }

    #if DEBUG
    /// Empty on each launch; RONEOGRAPH_SETTINGS sets the settings to start from, as JSON.
    private static func uiTesting() -> AppData {
        let root = URL.temporaryDirectory.appending(path: "UITesting", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let suite = "org.roneograph.app.uitesting"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = ProcessInfo.processInfo.environment["RONEOGRAPH_SETTINGS"].map { json in
            try! JSONDecoder().decode(ScannerSettings.self, from: Data(json.utf8))
        }
        return AppData(support: root.appending(path: "Support", directoryHint: .isDirectory), documents: documents, defaults: defaults, paperlessIdentifier: "\(suite).paperless", settings: settings)
    }
    #endif
}
