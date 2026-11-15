import Foundation

/// Decides when to capture a page automatically: when it has been held still long enough,
/// and only once per page, so turning pages in a pile does not capture the same page twice.
public struct CaptureTrigger: Sendable {
    public struct Configuration: Sendable {
        /// How long the page must stay still before it is captured.
        public var stableDuration: TimeInterval = 0.5
        /// How far any corner may move, as a fraction of the image, while the page counts as still.
        public var stillTolerance: Double = 0.015
        /// Smallest page area, as a fraction of the image, worth capturing.
        public var minimumArea: Double = 0.1
        /// Missed detections shorter than this do not restart the countdown.
        public var dropTolerance: TimeInterval = 0.25
        /// After a capture, the page must disappear this long to be considered gone.
        public var rearmLostDuration: TimeInterval = 0.4
        /// After a capture, a corner moving this far means another page.
        public var rearmMovement: Double = 0.1
        /// After a capture, content differing this much means another page.
        public var rearmContentDistance: Double = 0.06

        public init() {}
    }

    public enum State: Equatable, Sendable {
        case searching
        case steadying(progress: Double)
        case capture(Quad)
        case waitingForNextPage
    }

    public let configuration: Configuration
    private var anchor: (quad: Quad, since: TimeInterval)?
    private var lastSeen: TimeInterval?
    private var captured: (quad: Quad?, signature: PageSignature?)?
    private var lostSince: TimeInterval?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public var isWaitingForNextPage: Bool { captured != nil }

    public mutating func update(quad: Quad?, signature: PageSignature? = nil, at time: TimeInterval) -> State {
        let quad = quad.flatMap { Double($0.area) >= configuration.minimumArea ? $0 : nil }

        if let captured {
            guard isNewPage(quad: quad, signature: signature, captured: captured, at: time) else {
                return .waitingForNextPage
            }
            self.captured = nil
            anchor = nil
        }

        guard let quad else {
            if let lastSeen, time - lastSeen <= configuration.dropTolerance, let anchor {
                return .steadying(progress: progress(since: anchor.since, at: time))
            }
            anchor = nil
            return .searching
        }
        lastSeen = time

        guard let current = anchor, Double(quad.maxCornerDistance(to: current.quad)) <= configuration.stillTolerance else {
            anchor = (quad, time)
            return .steadying(progress: 0)
        }

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

    private func progress(since: TimeInterval, at time: TimeInterval) -> Double {
        min(1, (time - since) / configuration.stableDuration)
    }

    private mutating func isNewPage(quad: Quad?, signature: PageSignature?, captured: (quad: Quad?, signature: PageSignature?), at time: TimeInterval) -> Bool {
        guard let quad else {
            let since = lostSince ?? time
            lostSince = since
            return time - since >= configuration.rearmLostDuration
        }
        lostSince = nil
        guard let previous = captured.quad else { return true }
        if Double(quad.maxCornerDistance(to: previous)) > configuration.rearmMovement {
            return true
        }
        if let signature, let previous = captured.signature, signature.distance(to: previous) > configuration.rearmContentDistance {
            return true
        }
        return false
    }
}
