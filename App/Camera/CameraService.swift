@preconcurrency import AVFoundation
import CoreImage
import ScannerKit
import ScannerModels
import Synchronization
import Vision

enum CameraError: Error {
    case noPhotoData
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
    private let minimumFrameInterval: TimeInterval
    private let smudgeInterval: TimeInterval = 3
    private var lastFrameTime: TimeInterval = 0
    private var lastSmudgeCheck: TimeInterval = 0
    private let isDetecting = Atomic(false)
    private var device: AVCaptureDevice?
    private var inFlight: [Int64: PhotoDelegate] = [:]
    private var configured = false

    var onFrame: (@Sendable (LiveFrame) -> Void)?
    var onSmudge: (@Sendable (Float) -> Void)?

    init(extractor: PageExtractor, framesPerSecond: Double = 12) {
        self.extractor = extractor
        self.minimumFrameInterval = 1 / framesPerSecond
    }

    var isAvailable: Bool { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }

    var isAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }

    func requestAccess() async -> Bool {
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
            if let dimensions = CMVideoDimensions.photoSize(among: device.activeFormat.supportedMaxPhotoDimensions) {
                photoOutput.maxPhotoDimensions = dimensions
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
        guard time - lastFrameTime >= minimumFrameInterval, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
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
