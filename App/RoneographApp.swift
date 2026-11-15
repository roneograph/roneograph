import AVFoundation
import CoreImage
import ScannerKit
import ScannerModels
import SwiftUI

@main
struct RoneographApp: App {
    @State private var app: AppModel
    @State private var camera: CameraModel
    private let session: AVCaptureSession

    init() {
        let context = CIContext()
        let support = URL.applicationSupportDirectory.appending(path: "Scans", directoryHint: .isDirectory)
        let store = ScanStore(scansDirectory: support, documentsDirectory: .documentsDirectory)
        let app = AppModel(processor: ScanProcessor(store: store, context: context), settings: SettingsStore())
        _app = State(initialValue: app)
        let service = CameraService(extractor: PageExtractor(context: context))
        session = service.session
        _camera = State(initialValue: CameraModel(device: service, settings: app.settings))
        #if DEBUG
        Self.loadSamplePhotos(into: app)
        Self.openScreen(in: app)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(app: app, camera: camera, session: session)
        }
    }

    #if DEBUG
    /// Scans the photos of a folder, to try the app in the simulator, which has no camera; with RONEOGRAPH_SAMPLE_APPEND, adds them to the newest scan.
    private static func loadSamplePhotos(into app: AppModel) {
        guard let folder = ProcessInfo.processInfo.environment["RONEOGRAPH_SAMPLE_PHOTOS"] else { return }
        let photos = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".jpg") }.sorted()
        let append = ProcessInfo.processInfo.environment["RONEOGRAPH_SAMPLE_APPEND"]?.isEmpty == false
        let scan = append ? app.scans.first.flatMap { app.model(for: $0.id) } ?? app.startScan() : app.startScan()
        for photo in photos {
            if let data = FileManager.default.contents(atPath: "\(folder)/\(photo)") { scan.addPhoto(data, liveQuad: nil) }
        }
        app.finishCapture(scan)
    }

    /// Opens a screen on launch, for App Store screenshots: RONEOGRAPH_SCREEN=home, review or settings.
    private static func openScreen(in app: AppModel) {
        switch ProcessInfo.processInfo.environment["RONEOGRAPH_SCREEN"] {
        case "home":
            app.path = []
            for scan in app.scans.dropFirst() where scan.sent == nil {
                app.model(for: scan.id)?.markSent(.email)
            }
        case "review": if app.path.isEmpty { app.path = app.scans.first.map { [$0.id] } ?? [] }
        case "settings": app.showingSettings = true
        default: break
        }
    }
    #endif
}

struct RootView: View {
    @Bindable var app: AppModel
    let camera: CameraModel
    let session: AVCaptureSession
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
            CameraView(camera: camera, session: session, scan: scan, close: app.closeCamera) { app.finishCapture(scan) }
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
