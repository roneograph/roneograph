import AVFoundation
import Foundation
import Observation
import ScannerKit
import ScannerModels
import SwiftUI

@MainActor @Observable
final class CameraModel {
    enum Hint: Equatable {
        case pointAtPage, moveFarther, moveCloser, moreLight, cleanLens, holdStill, tapToCapture, added(Int)

        var text: String {
            switch self {
            case .pointAtPage: "Point at a page"
            case .moveFarther: "Move farther away"
            case .moveCloser: "Move closer"
            case .moreLight: "More light"
            case .cleanLens: "Clean the lens"
            case .holdStill: "Hold still"
            case .tapToCapture: "Tap to capture"
            case .added(let page): "Page \(page) added · next page"
            }
        }

        var systemImage: String? {
            switch self {
            case .moveFarther: "arrow.up.left.and.arrow.down.right"
            case .moveCloser: "arrow.down.right.and.arrow.up.left"
            case .moreLight: "sun.max"
            case .cleanLens: "hand.wave"
            case .added: "checkmark.circle.fill"
            default: nil
            }
        }
    }

    enum Access {
        case unknown, granted, denied
    }

    private(set) var detection: PageDetection?
    private(set) var imageSize = CGSize(width: 3, height: 4)
    private(set) var state: CaptureTrigger.State = .searching
    private(set) var lowLight = false
    private(set) var smudged = false
    /// Bumped on each capture, for the flash and the haptic.
    private(set) var captures = 0
    /// Bumped when a page gets locked, for the haptic.
    private(set) var locks = 0
    private(set) var access = Access.unknown
    private var pendingPhotos = 0
    var flash = FlashMode.off

    private let service: CameraService
    private let settings: SettingsStore
    private var trigger = CaptureTrigger()
    private var signature: PageSignature?
    private weak var scan: ScanModel?

    init(service: CameraService, settings: SettingsStore) {
        self.service = service
        self.settings = settings
        service.onFrame = { [weak self] frame in
            Task { @MainActor in self?.handle(frame) }
        }
        service.onSmudge = { [weak self] confidence in
            Task { @MainActor in self?.smudged = confidence >= 0.9 }
        }
    }

    var session: AVCaptureSession { service.session }

    var autoCapture: Bool {
        get { settings.value.autoCapture }
        set { settings.value.autoCapture = newValue }
    }

    var hint: Hint {
        switch state {
        case .pageCutOff: return .moveFarther
        case .pageTooSmall: return .moveCloser
        case .waitingForNextPage: return .added(pageCount)
        case .searching, .steadying, .capture:
            if smudged { return .cleanLens }
            if lowLight, detection == nil { return .moreLight }
            if detection == nil { return .pointAtPage }
            return autoCapture ? .holdStill : .tapToCapture
        }
    }

    /// Pages of the scan, including those still being taken or processed.
    var pageCount: Int {
        (scan?.scan.pages.count ?? 0) + (scan?.processing ?? 0) + pendingPhotos
    }

    var progress: Double {
        if case .steadying(let progress) = state, autoCapture { progress } else { 0 }
    }

    func start(scan: ScanModel) async {
        self.scan = scan
        trigger.reset()
        state = .searching
        if !CameraService.isAuthorized {
            access = await CameraService.requestAccess() ? .granted : .denied
        } else {
            access = .granted
        }
        if access == .granted { service.start() }
    }

    func stop() {
        service.stop()
    }

    func shutter() {
        trigger.didCapture(quad: detection?.quad, signature: signature)
        capture()
    }

    /// The last page was wrong: forget it and capture the page in view again.
    func retake() {
        trigger.reset()
    }

    private func handle(_ frame: LiveFrame) {
        let wasLocked = detection != nil
        detection = frame.detection
        imageSize = frame.imageSize
        signature = frame.signature
        lowLight = frame.lowLight
        if !wasLocked, frame.detection != nil { locks += 1 }

        trigger.configuration.stableDuration = autoCapture ? CaptureTrigger.Configuration().stableDuration : .infinity
        state = trigger.update(quad: frame.detection?.quad, signature: frame.signature, at: frame.time)
        if case .capture = state {
            capture()
        }
    }

    private func capture() {
        guard let scan else { return }
        let quad = detection?.quad
        let flash = flash
        captures += 1
        pendingPhotos += 1
        Task {
            defer { pendingPhotos -= 1 }
            do {
                scan.addPhoto(try await service.capturePhoto(flash: flash), liveQuad: quad)
            } catch {
                trigger.reset()
            }
        }
    }
}
