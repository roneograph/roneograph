import CoreGraphics
import Foundation

/// Decides when to capture a page automatically: when it has been held still long enough,
/// and only once per page, so turning pages in a pile does not capture the same page twice.
public struct CaptureTrigger: Sendable {
    public enum State: Equatable, Sendable {
        case searching
        /// A page is there but goes beyond the image: the phone is too close.
        case pageCutOff
        /// A page is there but too small to be read well: the phone is too far.
        case pageTooSmall
        case steadying(progress: Double)
        case capture(Quad)
        case waitingForNextPage
    }

    /// How long the page must stay still before it is captured.
    private let stableDuration: TimeInterval = 0.5
    /// How far any corner may move, as a fraction of the image, while the page counts as still.
    private let stillTolerance: Double = 0.015
    /// Smallest page area, as a fraction of the image, worth capturing.
    private let minimumArea: Double = 0.1
    /// A corner closer than this to the edge of the image means the page goes beyond it and is cut off.
    private let edgeMargin: Double = 0.02
    /// Missed detections shorter than this do not restart the countdown.
    private let dropTolerance: TimeInterval = 0.25
    /// After a capture, the page must disappear this long to be considered gone.
    private let rearmLostDuration: TimeInterval = 0.4
    /// After a capture, a corner moving this far means another page.
    private let rearmMovement: Double = 0.1
    /// After a capture, content differing this much means another page.
    private let rearmContentDistance: Double = 0.06

    /// False in manual mode: pages are still tracked, but only the shutter captures them.
    public var isAutomatic = true
    private var anchor: (quad: Quad, since: TimeInterval)?
    private var lastSeen: TimeInterval?
    private var captured: (quad: Quad?, signature: PageSignature?)?
    private var lostSince: TimeInterval?

    public init() {}

    public mutating func update(quad: Quad?, signature: PageSignature? = nil, at time: TimeInterval) -> State {
        let tooSmall = quad.map { Double($0.area) < minimumArea } ?? false
        let quad = tooSmall ? nil : quad

        if let captured {
            guard isNewPage(quad: quad, signature: signature, captured: captured, at: time) else {
                return .waitingForNextPage
            }
            self.captured = nil
        }

        if let quad, isCutOff(quad) {
            anchor = nil
            return .pageCutOff
        }

        guard let quad else {
            if let lastSeen, time - lastSeen <= dropTolerance, let anchor {
                return .steadying(progress: progress(since: anchor.since, at: time))
            }
            anchor = nil
            return tooSmall ? .pageTooSmall : .searching
        }
        lastSeen = time

        guard let current = anchor, Double(quad.maxCornerDistance(to: current.quad)) <= stillTolerance else {
            anchor = (quad, time)
            return .steadying(progress: 0)
        }

        guard isAutomatic else { return .steadying(progress: 0) }
        let progress = progress(since: current.since, at: time)
        guard progress >= 1 else { return .steadying(progress: progress) }

        didCapture(quad: quad, signature: signature)
        return .capture(quad)
    }

    /// Records a capture, automatic or manual, so the same page is not captured again.
    public mutating func didCapture(quad: Quad?, signature: PageSignature?) {
        captured = (quad, signature)
        anchor = nil
        lostSince = nil
    }

    public mutating func reset() {
        anchor = nil
        lastSeen = nil
        captured = nil
        lostSince = nil
    }

    private func isCutOff(_ quad: Quad) -> Bool {
        let margin = CGFloat(edgeMargin)
        return quad.corners.contains { $0.x < margin || $0.y < margin || $0.x > 1 - margin || $0.y > 1 - margin }
    }

    private func progress(since: TimeInterval, at time: TimeInterval) -> Double {
        min(1, (time - since) / stableDuration)
    }

    private mutating func isNewPage(quad: Quad?, signature: PageSignature?, captured: (quad: Quad?, signature: PageSignature?), at time: TimeInterval) -> Bool {
        guard let quad else {
            let since = lostSince ?? time
            lostSince = since
            return time - since >= rearmLostDuration
        }
        lostSince = nil
        guard let previous = captured.quad else { return true }
        if Double(quad.maxCornerDistance(to: previous)) > rearmMovement {
            return true
        }
        if let signature, let previous = captured.signature, signature.distance(to: previous) > rearmContentDistance {
            return true
        }
        return false
    }
}
