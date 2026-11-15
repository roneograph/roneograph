import CoreImage
import ScannerKit
import ScannerModels
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

    var body: some Scene {
        WindowGroup {
            RootView(app: app, camera: camera)
        }
    }

    #if DEBUG
    /// Scans the photos of a folder, to try the app in the simulator, which has no camera.
    private static func loadSamplePhotos(into app: AppModel) {
        guard let folder = ProcessInfo.processInfo.environment["PDFSCANNER_SAMPLE_PHOTOS"] else { return }
        let photos = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".jpg") }.sorted()
        let scan = app.startScan()
        for photo in photos {
            if let data = FileManager.default.contents(atPath: "\(folder)/\(photo)") { scan.addPhoto(data, liveQuad: nil) }
        }
        app.finishCapture(scan)
    }
    #endif
}

struct RootView: View {
    @Bindable var app: AppModel
    let camera: CameraModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $app.path) {
            HomeView(app: app)
                .navigationDestination(for: UUID.self) { id in
                    if let scan = app.model(for: id) {
                        ReviewView(app: app, scan: scan)
                    } else {
                        ContentUnavailableView("This scan is gone", systemImage: "doc")
                    }
                }
        }
        .fullScreenCover(item: $app.camera) { scan in
            CameraView(camera: camera, scan: scan, close: app.closeCamera) { app.finishCapture(scan) }
        }
        .sheet(isPresented: $app.showingSettings) {
            SettingsView(settings: app.settings)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.refresh() }
        }
    }
}

/// Settings, always the rightmost button at the top of Home and Review.
struct SettingsButton: View {
    let app: AppModel

    var body: some View {
        Button("Settings", systemImage: "gearshape") { app.showingSettings = true }
    }
}
