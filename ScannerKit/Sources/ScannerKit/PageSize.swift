import CoreGraphics

public enum Paper: String, Codable, Sendable, CaseIterable {
    case a4, letter

    /// Portrait size in points.
    public var size: CGSize {
        switch self {
        case .a4: CGSize(width: 595.276, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        }
    }

    var ratio: CGFloat { size.height / size.width }
}

/// Picks the PDF page size of a scanned page from its proportions, since a photo does not tell its physical size.
public struct PageSizing: Sendable {
    /// How far the proportions may be from A4 or Letter and still snap to it.
    public var tolerance: CGFloat = 0.08
    /// When the proportions are this close to halfway between A4 and Letter, the default paper wins.
    public var ambiguity: CGFloat = 0.02

    public init() {}

    /// Page size in points: A4 or Letter when the proportions match, otherwise the scan's proportions fitted inside the default paper.
    public func pageSize(forImage size: CGSize, defaultPaper: Paper) -> CGSize {
        guard size.width > 0, size.height > 0 else { return defaultPaper.size }
        let landscape = size.width > size.height
        let ratio = max(size.width, size.height) / min(size.width, size.height)
        let a4 = abs(ratio / Paper.a4.ratio - 1)
        let letter = abs(ratio / Paper.letter.ratio - 1)

        let portrait: CGSize
        if min(a4, letter) > tolerance {
            let paper = defaultPaper.size
            let scale = min(paper.width, paper.height / ratio)
            portrait = CGSize(width: scale, height: scale * ratio)
        } else if abs(a4 - letter) < ambiguity {
            portrait = defaultPaper.size
        } else {
            portrait = (a4 < letter ? Paper.a4 : Paper.letter).size
        }
        return landscape ? CGSize(width: portrait.height, height: portrait.width) : portrait
    }
}
