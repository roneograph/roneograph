import CoreGraphics
import Foundation
import ScannerKit
import ScannerKitTesting
@testable import ScannerModels
import Testing

final class FakeCamera: CameraDevice, @unchecked Sendable {
    var isAvailable = true
    var isAuthorized = true
    var grantsAccess = true
    var failsPhotos = false
    var onFrame: (@Sendable (LiveFrame) -> Void)?
    var onSmudge: (@Sendable (Float) -> Void)?
    var onInterruption: (@Sendable (Bool) -> Void)?
    private(set) var isRunning = false
    private(set) var photos = 0

    struct PhotoError: Error {}

    func requestAccess() async -> Bool { grantsAccess }
    func start() { isRunning = true }
    func stop() { isRunning = false }

    func capturePhoto(flash: FlashMode) async throws -> Data {
        photos += 1
        if failsPhotos { throw PhotoError() }
        return SyntheticPhoto.jpeg()
    }
}

@MainActor
@Suite(.serialized)
final class CameraModelTests {
    let page = Quad.rect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    let size = CGSize(width: 1200, height: 1600)
    let fixture: Fixture
    let device = FakeCamera()
    let camera: CameraModel
    let scan: ScanModel

    init() async throws {
        fixture = try Fixture()
        camera = CameraModel(device: device, settings: fixture.settings)
        scan = fixture.scanModel()
        await camera.start(scan: scan)
    }

    @Test func capturesAPageHeldStill() async {
        #expect(camera.hint == .pointAtPage)
        holdStill(camera, from: 0)
        #expect(camera.captures == 1)
        await camera.waitUntilIdle()
        #expect(device.photos == 1)
        #expect(fixture.store.all().first?.pages.count == 1)
        #expect(camera.hint == .added(1))
    }

    @Test func onlyTheShutterCapturesInManualMode() async {
        fixture.settings.value.autoCapture = false
        holdStill(camera, from: 0)
        #expect(camera.hint == .tapToCapture)
        #expect(camera.progress == 0)
        #expect(camera.captures == 0)

        camera.shutter()
        await camera.waitUntilIdle()
        #expect(device.photos == 1)
        holdStill(camera, from: 2)
        #expect(device.photos == 1)
    }

    @Test func saysWhenThePhotoFailsAndTriesAgain() async {
        device.failsPhotos = true
        holdStill(camera, from: 0)
        await camera.waitUntilIdle()
        #expect(camera.hint == .captureFailed)

        device.failsPhotos = false
        holdStill(camera, from: 1)
        await camera.waitUntilIdle()
        #expect(device.photos == 2)
        #expect(camera.hint == .added(1))
    }

    @Test func countsThePagesStillBeingTakenOrProcessed() async {
        camera.shutter()
        camera.shutter()
        #expect(camera.pageCount == 2)
        await camera.waitUntilIdle()
        #expect(camera.pageCount == 2)

        scan.addPhoto(SyntheticPhoto.jpeg(), liveQuad: nil)
        #expect(camera.pageCount == 3)
        await camera.waitUntilIdle()
        #expect(camera.pageCount == 3)
        #expect(scan.scan.pages.count == 3)
    }

    @Test func retakeCapturesThePageInViewAgain() async {
        holdStill(camera, from: 0)
        await camera.waitUntilIdle()
        camera.retake()
        holdStill(camera, from: 1)
        await camera.waitUntilIdle()
        #expect(device.photos == 2)
    }

    @Test func hintsHowToFrameThePage() async {
        camera.handle(LiveFrame(quad: nil, imageSize: size, time: 0, lowLight: true))
        #expect(camera.hint == .moreLight)
        camera.handle(LiveFrame(quad: .rect(x: 0.4, y: 0.4, width: 0.1, height: 0.1), imageSize: size, time: 0.1))
        #expect(camera.hint == .moveCloser)
        camera.handle(LiveFrame(quad: .rect(x: 0, y: 0.1, width: 1, height: 0.8), imageSize: size, time: 0.2))
        #expect(camera.hint == .moveFarther)
        camera.handle(LiveFrame(quad: page, imageSize: size, time: 0.3, lowLight: true))
        #expect(camera.hint == .holdStill)
        #expect(camera.locks == 1)
        camera.handle(LiveFrame(quad: nil, imageSize: size, time: 0.8))
        camera.handle(LiveFrame(quad: page, imageSize: size, time: 0.9))
        #expect(camera.locks == 2)
    }

    @Test func asksToCleanASmudgedLens() {
        camera.handleSmudge(0.89)
        #expect(camera.hint == .pointAtPage)
        camera.handleSmudge(0.9)
        #expect(camera.hint == .cleanLens)
        camera.handle(LiveFrame(quad: page, imageSize: size, time: 0))
        #expect(camera.hint == .cleanLens)
        camera.handleSmudge(0.2)
        #expect(camera.hint == .holdStill)
    }

    @Test func hintsWhatMattersMostFirst() async {
        camera.handleSmudge(1)
        camera.handle(LiveFrame(quad: nil, imageSize: size, time: 0, lowLight: true))
        #expect(camera.hint == .cleanLens)
        camera.handle(LiveFrame(quad: .rect(x: 0, y: 0.1, width: 1, height: 0.8), imageSize: size, time: 0.1))
        #expect(camera.hint == .moveFarther)

        device.failsPhotos = true
        camera.shutter()
        await camera.waitUntilIdle()
        #expect(camera.hint == .captureFailed)
    }

    @Test(arguments: [(true, false, CameraModel.Access.denied), (true, true, .granted), (false, true, .unavailable)])
    func asksForTheCamera(available: Bool, granted: Bool, access: CameraModel.Access) async {
        let device = FakeCamera()
        device.isAvailable = available
        device.isAuthorized = false
        device.grantsAccess = granted
        let camera = CameraModel(device: device, settings: fixture.settings)
        await camera.start(scan: fixture.scanModel())
        #expect(camera.access == access)
        #expect(device.isRunning == (access == .granted))
    }

    @Test func ignoresFramesAndTheShutterOnceStopped() async {
        camera.stop()
        holdStill(camera, from: 0)
        camera.shutter()
        await camera.waitUntilIdle()
        #expect(device.photos == 0)
        #expect(camera.quad == nil)
    }

    @Test func capturesNothingWhilePaused() async {
        camera.isPaused = true
        holdStill(camera, from: 0)
        camera.shutter()
        await camera.waitUntilIdle()
        #expect(device.photos == 0)

        camera.isPaused = false
        holdStill(camera, from: 2)
        await camera.waitUntilIdle()
        #expect(device.photos == 1)
    }

    @Test func saysWhenTheCameraIsInterruptedAndCapturesNothing() async {
        camera.handle(LiveFrame(quad: page, imageSize: size, time: 0))
        camera.handleInterruption(true)
        #expect(camera.hint == .cameraUnavailable)
        #expect(camera.quad == nil)
        #expect(!camera.canCapture)
        holdStill(camera, from: 1)
        camera.shutter()
        await camera.waitUntilIdle()
        #expect(device.photos == 0)

        camera.handleInterruption(false)
        #expect(camera.canCapture)
        holdStill(camera, from: 3)
        await camera.waitUntilIdle()
        #expect(device.photos == 1)
    }

    @Test func forgetsWhatTheLastSessionSawWhenStartedAgain() async {
        camera.handleSmudge(1)
        camera.handle(LiveFrame(quad: page, imageSize: size, time: 0, lowLight: true))
        camera.handleInterruption(true)
        camera.stop()
        await camera.start(scan: scan)
        #expect(camera.quad == nil)
        #expect(camera.hint == .pointAtPage)
    }

    /// Frames of the same page for one second.
    private func holdStill(_ camera: CameraModel, from start: TimeInterval) {
        for step in 0...10 {
            camera.handle(LiveFrame(quad: page, imageSize: size, time: start + Double(step) * 0.1))
        }
    }
}
