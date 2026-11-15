@preconcurrency import AVFoundation
import CoreImage
import ScannerKit
import Vision

/// What the live detection saw in one camera frame.
struct LiveFrame: Sendable {
    let detection: PageDetection?
    let signature: PageSignature?
    /// Size of the frame once upright.
    let imageSize: CGSize
    let time: TimeInterval
    /// The camera is near its highest sensitivity: the scene is dark.
    let lowLight: Bool
}

enum CameraError: Error {
    case noPhotoData
}

enum FlashMode: CaseIterable {
    case off, auto, on

    var next: FlashMode {
        switch self {
        case .off: .auto
        case .auto: .on
        case .on: .off
        }
    }

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
final class CameraService: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let extractor: PageExtractor
    private let minimumFrameInterval: TimeInterval
    private let smudgeInterval: TimeInterval = 3
    private var lastFrameTime: TimeInterval = 0
    private var lastSmudgeCheck: TimeInterval = 0
    private var device: AVCaptureDevice?
    private var inFlight: [Int64: PhotoDelegate] = [:]
    private var configured = false

    var onFrame: (@Sendable (LiveFrame) -> Void)?
    /// Called with the probability that the lens is smudged.
    var onSmudge: (@Sendable (Float) -> Void)?

    init(extractor: PageExtractor, framesPerSecond: Double = 12) {
        self.extractor = extractor
        self.minimumFrameInterval = 1 / framesPerSecond
    }

    static var isAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func start() {
        sessionQueue.async { [self] in
            if !configured {
                configured = true
                configure()
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capturePhoto(flash: FlashMode) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
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

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        self.device = device

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
            if let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                photoOutput.maxPhotoDimensions = largest
            }
            if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time - lastFrameTime >= minimumFrameInterval, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = time

        // Frames come in the sensor's landscape orientation; .right makes them portrait.
        let detection = extractor.detect(in: buffer, orientation: .right)
        let image = CIImage(cvPixelBuffer: buffer).oriented(.right)
        let signature = detection.flatMap { extractor.signature(of: image, quad: $0.quad) }
        let lowLight = device.map { $0.iso >= $0.activeFormat.maxISO * 0.7 } ?? false
        onFrame?(LiveFrame(detection: detection, signature: signature, imageSize: image.extent.size, time: time, lowLight: lowLight))

        if time - lastSmudgeCheck >= smudgeInterval, let onSmudge {
            lastSmudgeCheck = time
            let frame = FrameBox(buffer: buffer)
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

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            completion(.success(data))
        } else {
            completion(.failure(CameraError.noPhotoData))
        }
    }
}
