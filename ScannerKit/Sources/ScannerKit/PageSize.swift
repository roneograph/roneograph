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

/// Picks the PDF page size of a scanned page. A photo gives the proportions of a page, not its physical size,
/// so the size comes from the proportions when they are those of a known format, or from the size of the text.
public struct PageSizing: Sendable {
    /// ID-1 cards: identity cards, bank cards, driving licenses.
    public static let card = CGSize(width: 85.6 / 25.4 * 72, height: 53.98 / 25.4 * 72)

    /// How far the proportions may be from A4 or Letter and still snap to it.
    public var tolerance: CGFloat = 0.08
    /// When the proportions are this close to halfway between A4 and Letter, the default paper wins.
    public var ambiguity: CGFloat = 0.02
    public var cardTolerance: CGFloat = 0.025
    /// Height of a line of printed text, as Vision measures it, in points: about 3.7 mm on letters and invoices.
    public var textLineHeight: CGFloat = 10.5
    /// Estimated sizes are never smaller than this on their long side, in points.
    public var minimumLongSide: CGFloat = 50 / 25.4 * 72

    public init() {}

    /// Page size in points.
    /// - Parameter textLineHeight: median text line height as a share of the image's long side, nil when unknown or meaningless (pictures).
    public func pageSize(forImage size: CGSize, textLineHeight lineShare: Double? = nil, defaultPaper: Paper) -> CGSize {
        guard size.width > 0, size.height > 0 else { return defaultPaper.size }
        let landscape = size.width > size.height
        let ratio = max(size.width, size.height) / min(size.width, size.height)
        let a4 = abs(ratio / Paper.a4.ratio - 1)
        let letter = abs(ratio / Paper.letter.ratio - 1)

        let portrait: CGSize
        if min(a4, letter) <= tolerance {
            portrait = abs(a4 - letter) < ambiguity ? defaultPaper.size : (a4 < letter ? Paper.a4 : Paper.letter).size
        } else if abs(ratio / (Self.card.width / Self.card.height) - 1) <= cardTolerance {
            portrait = CGSize(width: Self.card.height, height: Self.card.width)
        } else {
            let paper = defaultPaper.size
            let fitted = min(paper.width, paper.height / ratio)
            var width = fitted
            if let lineShare, lineShare > 0 {
                let longSide = max(minimumLongSide, textLineHeight / CGFloat(lineShare))
                width = min(fitted, longSide / ratio)
            }
            portrait = CGSize(width: width, height: width * ratio)
        }
        return landscape ? CGSize(width: portrait.height, height: portrait.width) : portrait
    }
}
