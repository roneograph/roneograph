import Foundation
import ScannerKit
import ScannerModels

/// Where the app keeps its settings, scans, PDFs and Paperless tokens; UI tests get fresh ones, apart from the app's own data.
struct AppData {
    var support = URL.applicationSupportDirectory
    var documents = URL.documentsDirectory
    var defaults = UserDefaults.standard
    var paperlessIdentifier = "org.roneograph.app.paperless"
    /// The settings to start from instead of the saved ones.
    var settings: ScannerSettings?
    /// Sends the requests made to Paperless while the app is open.
    var paperlessFetch: Archiver.Fetch = PaperlessHTTP.fetch
    /// Gives a token to the owners with a server, for a Paperless server that takes any.
    var connectsOwners = false

    static var current: AppData {
        #if DEBUG
        if isUITesting { return uiTesting() }
        #endif
        return AppData()
    }

    #if DEBUG
    static var isUITesting: Bool { ProcessInfo.processInfo.environment["RONEOGRAPH_UI_TESTING"] != nil }

    /// Empty on each launch; RONEOGRAPH_SETTINGS sets the settings to start from, as JSON.
    /// RONEOGRAPH_PAPERLESS connects the owners with a server to one that lists the names it gives, as {"correspondents": ["Lumen"], "document_types": ["Invoice"]}, and refuses anything else.
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
        var data = AppData(support: root.appending(path: "Support", directoryHint: .isDirectory), documents: documents, defaults: defaults, paperlessIdentifier: "\(suite).paperless", settings: settings)
        if let json = ProcessInfo.processInfo.environment["RONEOGRAPH_PAPERLESS"] {
            data.paperlessFetch = listing(try! JSONDecoder().decode([String: [String]].self, from: Data(json.utf8)))
            data.connectsOwners = true
        }
        return data
    }

    private static func listing(_ lists: [String: [String]]) -> Archiver.Fetch {
        { request in
            let names = request.httpMethod == "GET" ? request.url.flatMap { lists[$0.lastPathComponent] } : nil
            let results = (names ?? []).enumerated().map { ["id": $0.offset + 1, "name": $0.element] as [String: Any] }
            let body = try JSONSerialization.data(withJSONObject: ["next": NSNull(), "results": results])
            return (body, HTTPURLResponse(url: request.url!, statusCode: names == nil ? 403 : 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    #endif
}
