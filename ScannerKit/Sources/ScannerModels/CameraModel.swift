import CoreGraphics
import Foundation
import Observation
import ScannerKit

/// What the live detection saw in one camera frame.
public struct LiveFrame: Sendable {
    public let quad: Quad?
    public let signature: PageSignature?
    /// Size of the frame once upright.
    public let imageSize: CGSize
    public let time: TimeInterval
    /// The camera is near its highest sensitivity: the scene is dark.
    public let lowLight: Bool

    public init(quad: Quad?, signature: PageSignature? = nil, imageSize: CGSize, time: TimeInterval, lowLight: Bool = false) {
        self.quad = quad
        self.signature = signature
        self.imageSize = imageSize
        self.time = time
        self.lowLight = lowLight
    }
}

public enum FlashMode: Sendable {
    case off, auto, on

    public var next: FlashMode {
        switch self {
        case .off: .auto
        case .auto: .on
        case .on: .off
        }
    }
}

/// The back camera: live frames for the detection, lens checks, and full resolution photos.
public protocol CameraDevice: AnyObject, Sendable {
    /// False on devices without a back camera apps can use, such as Apple Vision Pro.
    var isAvailable: Bool { get }
    var isAuthorized: Bool { get }
    var onFrame: (@Sendable (LiveFrame) -> Void)? { get set }
    /// Called with the probability that the lens is smudged.
    var onSmudge: (@Sendable (Float) -> Void)? { get set }
    /// Called with true when the system takes the camera away, such as for a call, and false when it gives it back.
    var onInterruption: (@Sendable (Bool) -> Void)? { get set }
    func requestAccess() async -> Bool
    func start()
    func stop()
    func capturePhoto(flash: FlashMode) async throws -> Data
}

/// The camera screen: tracks the page in the live frames, captures it when it holds still or on the shutter, and tells what to do.
@MainActor @Observable
public final class CameraModel {
    public enum Hint: Equatable, Sendable {
        case pointAtPage, moveFarther, moveCloser, moreLight, cleanLens, holdStill, tapToCapture, captureFailed, cameraUnavailable, added(Int)

        public var text: String {
            switch self {
            case .pointAtPage: "Point at a page"
            case .moveFarther: "Move farther away"
            case .moveCloser: "Move closer"
            case .moreLight: "More light"
            case .cleanLens: "Clean the lens"
            case .holdStill: "Hold still"
            case .tapToCapture: "Tap to capture"
            case .captureFailed: "The photo failed · try again"
            case .cameraUnavailable: "Camera unavailable"
            case .added(let page): "Page \(page) added · next page"
            }
        }

        public var systemImage: String? {
            switch self {
            case .moveFarther: "arrow.up.left.and.arrow.down.right"
            case .moveCloser: "arrow.down.right.and.arrow.up.left"
            case .moreLight: "sun.max"
            case .cleanLens: "hand.wave"
            case .captureFailed: "exclamationmark.triangle.fill"
            case .cameraUnavailable: "video.slash"
            case .added: "checkmark.circle.fill"
            default: nil
            }
        }
    }

    public enum Access: Sendable {
        case unknown, granted, denied, unavailable
    }

    public private(set) var quad: Quad?
    public private(set) var imageSize = CGSize(width: 3, height: 4)
    public private(set) var state: CaptureTrigger.State = .searching
    private var lowLight = false
    private var smudged = false
    private var captureFailed = false
    private var isRunning = false
    private var isInterrupted = false
    /// Set while something covers the camera, such as the last page sheet: nothing is captured.
    public var isPaused = false
    /// Bumped on each capture, for the flash and the haptic.
    public private(set) var captures = 0
    /// Bumped when a page gets locked, for the haptic.
    public private(set) var locks = 0
    public private(set) var access = Access.unknown
    public var flash = FlashMode.off

    private let device: CameraDevice
    private let settings: SettingsStore
    @ObservationIgnored private var trigger = CaptureTrigger()
    @ObservationIgnored private var signature: PageSignature?
    private var photoTasks: [UUID: Task<Void, Never>] = [:]
    private weak var scan: ScanModel?

    public init(device: CameraDevice, settings: SettingsStore) {
        self.device = device
        self.settings = settings
        device.onFrame = { [weak self] frame in
            Task { @MainActor in self?.handle(frame) }
        }
        device.onSmudge = { [weak self] confidence in
            Task { @MainActor in self?.handleSmudge(confidence) }
        }
        device.onInterruption = { [weak self] interrupted in
            Task { @MainActor in self?.handleInterruption(interrupted) }
        }
    }

    /// The shutter can take a photo: the camera runs and nothing covers it.
    public var canCapture: Bool { isRunning && !isInterrupted && !isCovered }

    /// The last page sheet or the failure alert is shown.
    private var isCovered: Bool { isPaused || scan?.failure != nil }

    public var autoCapture: Bool {
        get { settings.value.autoCapture }
        set { settings.value.autoCapture = newValue }
    }

    public var hint: Hint {
        if isInterrupted { return .cameraUnavailable }
        switch state {
        case .pageCutOff: return .moveFarther
        case .pageTooSmall: return .moveCloser
        case .waitingForNextPage: return .added(pageCount)
        case .searching, .steadying, .capture:
            if captureFailed { return .captureFailed }
            if smudged { return .cleanLens }
            if lowLight, quad == nil { return .moreLight }
            if quad == nil { return .pointAtPage }
            return autoCapture ? .holdStill : .tapToCapture
        }
    }

    /// Pages of the scan, including those still being taken or processed.
    public var pageCount: Int {
        (scan?.scan.pages.count ?? 0) + (scan?.processing ?? 0) + photoTasks.count
    }

    public var progress: Double {
        if case .steadying(let progress) = state, autoCapture { progress } else { 0 }
    }

    public func start(scan: ScanModel) async {
        self.scan = scan
        trigger.reset()
        state = .searching
        quad = nil
        signature = nil
        lowLight = false
        smudged = false
        captureFailed = false
        isInterrupted = false
        if !device.isAvailable {
            access = .unavailable
        } else if !device.isAuthorized {
            access = await device.requestAccess() ? .granted : .denied
        } else {
            access = .granted
        }
        if access == .granted {
            isRunning = true
            device.start()
        }
    }

    public func stop() {
        isRunning = false
        quad = nil
        device.stop()
    }

    public func shutter() {
        guard canCapture else { return }
        trigger.didCapture(quad: quad, signature: signature)
        capture()
    }

    /// Lets the page in view be captured again, once the last page was deleted to retake it.
    public func retake() {
        trigger.reset()
    }

    /// Waits until every photo taken is added to the scan and processed.
    public func waitUntilIdle() async {
        while let task = photoTasks.values.first { await task.value }
        await scan?.waitUntilIdle()
    }

    func handle(_ frame: LiveFrame) {
        guard isRunning, !isInterrupted else { return }
        let wasLocked = quad != nil
        quad = frame.quad
        imageSize = frame.imageSize
        signature = frame.signature
        lowLight = frame.lowLight
        if !wasLocked, frame.quad != nil { locks += 1 }

        guard !isCovered else { return }
        trigger.isAutomatic = autoCapture
        state = trigger.update(quad: frame.quad, signature: frame.signature, at: frame.time)
        if case .capture = state {
            capture()
        }
    }

    func handleSmudge(_ confidence: Float) {
        smudged = confidence >= 0.9
    }

    func handleInterruption(_ interrupted: Bool) {
        isInterrupted = interrupted
        quad = nil
        signature = nil
        trigger.reset()
        state = .searching
    }

    private func capture() {
        guard let scan, canCapture else { return }
        let quad = quad, flash = flash, device = device
        captures += 1
        captureFailed = false
        let id = UUID()
        photoTasks[id] = Task {
            defer { photoTasks[id] = nil }
            if let photo = try? await device.capturePhoto(flash: flash), scan.addPhoto(photo, liveQuad: quad) { return }
            captureFailed = true
            trigger.reset()
            state = .searching
        }
    }
}
