import AVFoundation
import CoreImage
import ScannerKit
import ScannerModels
import Synchronization
import Vision

enum CameraError: Error {
    case noPhotoData
    case notReady
}

extension FlashMode {
    var systemImage: String {
        switch self {
        case .off: "bolt.slash"
        case .auto: "bolt.badge.automatic"
        case .on: "bolt.fill"
        }
    }

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: .off
        case .auto: .auto
        case .on: .on
        }
    }
}

/// Owns the capture session: runs page detection on the video frames, checks the lens now and then, and takes full resolution photos.
final class CameraService: NSObject, CameraDevice, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "org.roneograph.camera.session")
    private let videoQueue = DispatchQueue(label: "org.roneograph.camera.video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let extractor: PageExtractor
    private let normalFrameInterval: TimeInterval
    /// Longer under system pressure.
    private let frameInterval: Atomic<Double>
    private let smudgeInterval: TimeInterval = 3
    private var lastFrameTime: TimeInterval = 0
    private var lastSmudgeCheck: TimeInterval = 0
    private let isDetecting = Atomic(false)
    private var device: AVCaptureDevice?
    private var inFlight: [Int64: PhotoDelegate] = [:]
    private var configured = false
    /// Whether the camera screen wants the session running, to restart it after the media services reset.
    private var wantsRunning = false
    private var pressureObservation: NSKeyValueObservation?

    var onFrame: (@Sendable (LiveFrame) -> Void)?
    var onSmudge: (@Sendable (Float) -> Void)?
    var onInterruption: (@Sendable (Bool) -> Void)?

    init(extractor: PageExtractor, framesPerSecond: Double = 12) {
        self.extractor = extractor
        normalFrameInterval = 1 / framesPerSecond
        frameInterval = Atomic(1 / framesPerSecond)
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sessionWasInterrupted), name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(self, selector: #selector(sessionInterruptionEnded), name: AVCaptureSession.interruptionEndedNotification, object: session)
        center.addObserver(self, selector: #selector(sessionRuntimeError), name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    var isAvailable: Bool { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }

    var isAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func start() {
        sessionQueue.async { [self] in
            wantsRunning = true
            if !configured { configured = configure() }
            if configured, !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            wantsRunning = false
            if session.isRunning { session.stopRunning() }
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        onInterruption?(true)
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        onInterruption?(false)
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError, error.code == .mediaServicesWereReset else {
            onInterruption?(true)
            return
        }
        sessionQueue.async { [self] in
            if wantsRunning, !session.isRunning { session.startRunning() }
        }
    }

    /// Under pressure, fewer frames are checked for a page.
    private func adapt(to pressure: AVCaptureDevice.SystemPressureState.Level) {
        let interval: Double = switch pressure {
        case .serious: 1 / 4
        case .critical, .shutdown: 1
        default: normalFrameInterval
        }
        frameInterval.store(interval, ordering: .relaxed)
    }

    func capturePhoto(flash: FlashMode) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard session.isRunning, !session.isInterrupted, let connection = photoOutput.connection(with: .video), connection.isActive, connection.isEnabled else {
                    continuation.resume(throwing: CameraError.notReady)
                    return
                }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
                settings.photoQualityPrioritization = .balanced
                if photoOutput.supportedFlashModes.contains(flash.avFlashMode) {
                    settings.flashMode = flash.avFlashMode
                }
                let id = settings.uniqueID
                let delegate = PhotoDelegate { [self] result in
                    sessionQueue.async { self.inFlight[id] = nil }
                    continuation.resume(with: result)
                }
                inFlight[id] = delegate
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    /// False when the camera cannot be set up; the next start tries again.
    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return false }
        session.addInput(input)
        self.device = device
        pressureObservation = device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] device, _ in
            self?.adapt(to: device.systemPressureState.level)
        }

        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
            if let dimensions = CMVideoDimensions.photoSize(among: device.activeFormat.supportedMaxPhotoDimensions) {
                photoOutput.maxPhotoDimensions = dimensions
            }
            if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        return true
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time - lastFrameTime >= frameInterval.load(ordering: .relaxed), let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              isDetecting.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged else { return }
        lastFrameTime = time

        let frame = FrameBox(buffer: buffer)
        let lowLight = device.map { $0.iso >= $0.activeFormat.maxISO * 0.7 } ?? false
        let onFrame = onFrame
        Task { [self] in
            defer { isDetecting.store(false, ordering: .releasing) }
            // Frames come in the sensor's landscape orientation; .right makes them portrait.
            let quad = await extractor.detect(in: frame.buffer, orientation: .right)
            let image = CIImage(cvPixelBuffer: frame.buffer).oriented(.right)
            let signature = quad.flatMap { extractor.signature(of: image, quad: $0) }
            onFrame?(LiveFrame(quad: quad, signature: signature, imageSize: image.extent.size, time: time, lowLight: lowLight))
        }

        if time - lastSmudgeCheck >= smudgeInterval, let onSmudge {
            lastSmudgeCheck = time
            Task.detached(priority: .utility) {
                if let observation = try? await DetectLensSmudgeRequest().perform(on: frame.buffer, orientation: .right) {
                    onSmudge(observation.confidence)
                }
            }
        }
    }
}

private struct FrameBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    private var result: Result<Data, Error>?

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(CameraError.noPhotoData)
        }
    }

    /// Always called last, even when the capture failed before a photo came.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        completion(result ?? .failure(error ?? CameraError.noPhotoData))
    }
}
