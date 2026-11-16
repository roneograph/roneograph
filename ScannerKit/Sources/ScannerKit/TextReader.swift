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

/// Reads the lines of text of an upright page, to suggest a file name and to make the PDF searchable.
public struct TextReader: Sendable {
    private let longSide: CGFloat = 1600

    public init() {}

    public func lines(in page: CIImage) async -> [TextLine] {
        let image = page.atOrigin.scaled(by: page.scale(toLongSide: longSide))
        return await VisionQueue.run {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(ciImage: image).perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return TextLine(text: candidate.string, frame: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height), confidence: candidate.confidence)
            }
        }
    }
}
