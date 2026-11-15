import CoreImage
import Vision

/// Reads the lines of text of an upright page, to suggest a file name. The text is never stored.
public struct TextReader: Sendable {
    public var longSide: CGFloat = 1600

    public init() {}

    public func lines(in page: CIImage) -> [TextLine] {
        let image = page.atOrigin.scaled(by: page.scale(toLongSide: longSide))
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
