import ScannerKit
import Testing

struct CaptureTriggerTests {
    let page = Quad.rect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

    @Test func capturesAPageHeldStill() {
        var trigger = CaptureTrigger()
        #expect(trigger.update(quad: page, at: 0) == .steadying(progress: 0))
        #expect(trigger.update(quad: page.offset(by: 0.005), at: 0.25) == .steadying(progress: 0.5))
        #expect(trigger.update(quad: page, at: 0.5) == .capture(page))
    }

    @Test func movingRestartsTheCountdown() {
        var trigger = CaptureTrigger()
        _ = trigger.update(quad: page, at: 0)
        _ = trigger.update(quad: page, at: 0.4)
        let moved = page.offset(by: 0.05)
        #expect(trigger.update(quad: moved, at: 0.45) == .steadying(progress: 0))
        #expect(trigger.update(quad: moved, at: 0.8) != .capture(moved))
        #expect(trigger.update(quad: moved, at: 1.0) == .capture(moved))
    }

    @Test func slowDriftCountsAsMovement() {
        var trigger = CaptureTrigger()
        _ = trigger.update(quad: page, at: 0)
        _ = trigger.update(quad: page.offset(by: 0.01), at: 0.2)
        #expect(trigger.update(quad: page.offset(by: 0.02), at: 0.4) == .steadying(progress: 0))
    }

    @Test func ignoresSmallPages() {
        var trigger = CaptureTrigger()
        let small = Quad.rect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        #expect(trigger.update(quad: small, at: 0) == .searching)
        #expect(trigger.update(quad: small, at: 1) == .searching)
    }

    @Test func toleratesShortDetectionDrops() {
        var trigger = CaptureTrigger()
        _ = trigger.update(quad: page, at: 0)
        #expect(trigger.update(quad: nil, at: 0.2) == .steadying(progress: 0.4))
        #expect(trigger.update(quad: page, at: 0.5) == .capture(page))
    }

    @Test func longDetectionDropsRestart() {
        var trigger = CaptureTrigger()
        _ = trigger.update(quad: page, at: 0)
        #expect(trigger.update(quad: nil, at: 0.3) == .searching)
        #expect(trigger.update(quad: page, at: 0.5) == .steadying(progress: 0))
    }

    @Test func doesNotCaptureTheSamePageTwice() {
        var trigger = CaptureTrigger()
        _ = trigger.update(quad: page, at: 0)
        #expect(trigger.update(quad: page, at: 0.5) == .capture(page))
        #expect(trigger.update(quad: page, at: 1) == .waitingForNextPage)
        #expect(trigger.update(quad: page, at: 5) == .waitingForNextPage)
    }

    @Test func rearmsWhenThePageDisappears() {
        var trigger = CaptureTrigger()
        _ = trigger.update(quad: page, at: 0)
        _ = trigger.update(quad: page, at: 0.5)
        #expect(trigger.update(quad: nil, at: 0.6) == .waitingForNextPage)
        #expect(trigger.update(quad: nil, at: 1.05) == .searching)
        #expect(trigger.update(quad: page, at: 1.1) == .steadying(progress: 0))
        #expect(trigger.update(quad: page, at: 1.6) == .capture(page))
    }

    @Test func aBriefOcclusionDoesNotRearm() {
        var trigger = CaptureTrigger()
        _ = trigger.update(quad: page, at: 0)
        _ = trigger.update(quad: page, at: 0.5)
        #expect(trigger.update(quad: nil, at: 0.6) == .waitingForNextPage)
        #expect(trigger.update(quad: page, at: 0.7) == .waitingForNextPage)
        #expect(trigger.update(quad: nil, at: 0.8) == .waitingForNextPage)
        #expect(trigger.update(quad: nil, at: 1.1) == .waitingForNextPage)
    }

    @Test func rearmsWhenThePageMovesAway() {
        var trigger = CaptureTrigger()
        _ = trigger.update(quad: page, at: 0)
        _ = trigger.update(quad: page, at: 0.5)
        let other = page.offset(by: 0.15)
        #expect(trigger.update(quad: other, at: 0.6) == .steadying(progress: 0))
    }

    @Test func rearmsWhenTheContentChanges() {
        var trigger = CaptureTrigger()
        let first = PageSignature.uniform(0.5, stripe: 0)
        let second = PageSignature.uniform(0.5, stripe: 8)
        _ = trigger.update(quad: page, signature: first, at: 0)
        _ = trigger.update(quad: page, signature: first, at: 0.5)
        #expect(trigger.update(quad: page, signature: first, at: 0.6) == .waitingForNextPage)
        #expect(trigger.update(quad: page, signature: second, at: 0.7) == .steadying(progress: 0))
        #expect(trigger.update(quad: page, signature: second, at: 1.25) == .capture(page))
    }

    @Test func aManualCaptureWithoutAPageRearmsWhenAPageAppears() {
        var trigger = CaptureTrigger()
        trigger.didCapture(quad: nil, signature: nil)
        #expect(trigger.update(quad: page, at: 0) == .steadying(progress: 0))
    }
}

extension PageSignature {
    /// A uniform page with a dark horizontal band starting at row `stripe`.
    static func uniform(_ level: Float, stripe: Int) -> PageSignature {
        var values = [Float](repeating: level, count: width * height)
        for row in stripe..<min(height, stripe + 4) {
            for column in 0..<width { values[row * width + column] = 0 }
        }
        return PageSignature(luminance: values)
    }
}
