import AVFoundation
import CoreImage
import Foundation
import Observation
import ScannerKit

@MainActor @Observable
final class CameraModel {
    private(set) var detection: PageDetection?
    private(set) var imageSize = CGSize(width: 3, height: 4)
    private(set) var state: CaptureTrigger.State = .searching
    private(set) var processing = 0
    private(set) var captureCount = 0
    private(set) var lastError: String?
    var autoCapture = true

    let session: SpikeSession
    let exporter: PDFExporter
    private let camera: CameraService
    private let processor: PageProcessor
    private var trigger = CaptureTrigger()
    private var lastSignature: PageSignature?

    init(session: SpikeSession, camera: CameraService, processor: PageProcessor, exporter: PDFExporter) {
        self.session = session
        self.exporter = exporter
        self.camera = camera
        self.processor = processor
        camera.onFrame = { [weak self] frame in
            Task { @MainActor in self?.handle(frame) }
        }
    }

    var captureSession: AVCaptureSessionBox { AVCaptureSessionBox(session: camera.session) }

    var hint: String {
        switch state {
        case .searching: "Point at a page"
        case .pageCutOff: "Move farther away"
        case .steadying: autoCapture ? "Hold still" : "Tap to capture"
        case .capture: "Capturing"
        case .waitingForNextPage: "Page \(captureCount) added · next page"
        }
    }

    var progress: Double {
        if case .steadying(let progress) = state, autoCapture { progress } else { 0 }
    }

    func start() { camera.start() }
    func stop() { camera.stop() }

    func shutter() {
        trigger.didCapture(quad: detection?.quad, signature: lastSignature)
        capture(automatic: false)
    }

    func newSession() {
        session.reset()
        trigger.reset()
        captureCount = 0
    }

    private func handle(_ frame: LiveFrame) {
        detection = frame.detection
        imageSize = frame.imageSize
        lastSignature = frame.signature
        session.liveStats.frames += 1
        session.liveStats.framesWithPage += frame.detection == nil ? 0 : 1
        session.liveStats.totalDetectionDuration += frame.detectionDuration

        guard autoCapture else {
            state = frame.detection == nil ? .searching : .steadying(progress: 0)
            return
        }
        state = trigger.update(quad: frame.detection?.quad, signature: frame.signature, at: frame.time)
        if case .capture = state {
            capture(automatic: true)
        }
    }

    private func capture(automatic: Bool) {
        let live = detection
        let number = session.nextNumber + processing
        let directory = session.directory
        let camera = camera, processor = processor
        captureCount += 1
        processing += 1
        Task {
            defer { processing -= 1 }
            do {
                let photo = try await camera.capturePhoto()
                let page = try await Task.detached(priority: .userInitiated) {
                    try processor.process(photo, number: number, automatic: automatic, liveDetection: live, directory: directory)
                }.value
                if directory == session.directory { session.add(page) }
            } catch {
                lastError = "\(error)"
            }
        }
    }
}

/// Lets the non-Sendable session cross into the preview view.
struct AVCaptureSessionBox: @unchecked Sendable {
    let session: AVCaptureSession
}
