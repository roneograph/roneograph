import CoreImage
import ScannerKit
import SwiftUI

@main
struct PDFScannerApp: App {
    @State private var app: AppModel
    @State private var camera: CameraModel

    init() {
        let context = CIContext()
        let support = URL.applicationSupportDirectory.appending(path: "Scans", directoryHint: .isDirectory)
        let store = ScanStore(scansDirectory: support, documentsDirectory: .documentsDirectory)
        let app = AppModel(processor: ScanProcessor(store: store, context: context), settings: SettingsStore())
        _app = State(initialValue: app)
        _camera = State(initialValue: CameraModel(service: CameraService(extractor: PageExtractor(context: context)), settings: app.settings))
        #if DEBUG
        Self.loadSamplePhotos(into: app)
        #endif
    }

    #if DEBUG
    /// Scans the photos of a folder, to try the app in the simulator, which has no camera.
    private static func loadSamplePhotos(into app: AppModel) {
        guard let folder = ProcessInfo.processInfo.environment["PDFSCANNER_SAMPLE_PHOTOS"] else { return }
        let photos = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".jpg") }.sorted()
        app.newScan()
        for photo in photos {
            if let data = FileManager.default.contents(atPath: "\(folder)/\(photo)") { app.scan.addPhoto(data, liveQuad: nil) }
        }
        app.finishCapture()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                switch app.screen {
                case .camera:
                    CameraView(camera: camera, app: app)
                case .review:
                    ReviewView(app: app, scan: app.scan)
                }
            }
            .animation(.default, value: app.screen)
        }
    }
}
