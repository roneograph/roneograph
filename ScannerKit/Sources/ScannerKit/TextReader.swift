import CoreImage
import Vision

/// A line of text read on a page, with its frame normalized to the upright page, origin at the top left.
public struct TextLine: Equatable, Sendable {
    public var text: String
    public var frame: CGRect
    /// Recognition confidence, from 0 to 1.
    public var confidence: Float

    public init(text: String, frame: CGRect, confidence: Float = 1) {
        self.text = text
        self.frame = frame
        self.confidence = confidence
    }
}

extension RecognizeTextRequest {
    /// The accurate recognizer, reading text of any size: the default skips text smaller than 1/32 of the image and measures lines coarsely.
    /// The revision is pinned, as the confidence thresholds of DocumentDetector were tuned on it.
    static func page() -> Self {
        var request = RecognizeTextRequest(.revision3)
        request.recognitionLevel = .accurate
        request.minimumTextHeightFraction = 0
        return request
    }
}

/// Reads the lines of text of an upright page, to suggest a file name and to make the PDF searchable.
public struct TextReader: Sendable {
    private let longSide: CGFloat = 1600

    public init() {}

    public func lines(in page: CIImage) async -> [TextLine] {
        let image = page.atOrigin.scaled(by: page.scale(toLongSide: longSide))
        var request = RecognizeTextRequest.page()
        request.automaticallyDetectsLanguage = true
        let observations = (try? await request.perform(on: image)) ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox.cgRect
            return TextLine(text: candidate.string, frame: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height), confidence: candidate.confidence)
        }
    }
}
