import CoreGraphics
import ScannerKit
import Testing

struct PageSizingTests {
    let sizing = PageSizing()

    @Test func a4IsTheRatioOfItsMillimeters() {
        #expect(abs(Paper.a4.aspectRatio - 210 / 297) < 0.001)
    }

    @Test func snapsToA4() {
        #expect(sizing.pageSize(forImage: CGSize(width: 1704, height: 2471), defaultPaper: .letter) == Paper.a4.size)
    }

    @Test func snapsToLetter() {
        #expect(sizing.pageSize(forImage: CGSize(width: 1700, height: 2210), defaultPaper: .a4) == Paper.letter.size)
    }

    @Test func usesTheDefaultPaperHalfwayBetweenA4AndLetter() {
        let halfway = CGSize(width: 1000, height: 1350)
        #expect(sizing.pageSize(forImage: halfway, defaultPaper: .a4) == Paper.a4.size)
        #expect(sizing.pageSize(forImage: halfway, defaultPaper: .letter) == Paper.letter.size)
    }

    @Test func keepsTheProportionsOfOtherShapesInsideTheDefaultPaperWithoutText() {
        let receipt = sizing.pageSize(forImage: CGSize(width: 800, height: 2400), defaultPaper: .a4)
        #expect(abs(receipt.height - Paper.a4.size.height) < 0.01)
        #expect(abs(receipt.width - Paper.a4.size.height / 3) < 0.01)
    }

    @Test func givesCardsTheirRealSize() {
        let card = sizing.pageSize(forImage: CGSize(width: 1859, height: 1165), defaultPaper: .a4)
        #expect(abs(card.width / 72 * 25.4 - 85.6) < 0.1)
        #expect(abs(card.height / 72 * 25.4 - 54) < 0.1)
    }

    @Test func estimatesTheSizeOfOtherShapesFromTheirText() {
        // A receipt whose text lines are 1/50 of its height: about 185 mm tall.
        let receipt = sizing.pageSize(forImage: CGSize(width: 800, height: 2400), textLineHeight: 0.02, defaultPaper: .a4)
        #expect(abs(receipt.height / 72 * 25.4 - 185) < 1)
        #expect(abs(receipt.height / receipt.width - 3) < 0.01)
    }

    @Test func neverMakesAnEstimatedPageBiggerThanTheDefaultPaperOrTiny() {
        let tinyText = sizing.pageSize(forImage: CGSize(width: 800, height: 2400), textLineHeight: 0.001, defaultPaper: .a4)
        #expect(abs(tinyText.height - Paper.a4.size.height) < 0.01)
        let hugeText = sizing.pageSize(forImage: CGSize(width: 800, height: 2400), textLineHeight: 0.5, defaultPaper: .a4)
        #expect(abs(hugeText.height / 72 * 25.4 - 50) < 0.1)
    }

    @Test func ignoresTheTextOfA4Pages() {
        #expect(sizing.pageSize(forImage: CGSize(width: 1704, height: 2471), textLineHeight: 0.05, defaultPaper: .a4) == Paper.a4.size)
    }

    @Test func keepsLandscapePagesLandscape() {
        #expect(sizing.pageSize(forImage: CGSize(width: 2471, height: 1704), defaultPaper: .a4) == CGSize(width: Paper.a4.size.height, height: Paper.a4.size.width))
    }
}
