import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ScannerKit

/// A 1200 × 1600 photo of a page with text lines on a dark desk.
public enum SyntheticPhoto {
    public static let size = CGSize(width: 1200, height: 1600)

    public static func render(page: Quad?, contentAtTop: Bool = true, paper: CGFloat = 0.97) -> CIImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(red: 0.32, green: 0.24, blue: 0.17, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        if let page {
            let corners = page.scaled(to: size)
            context.setFillColor(red: paper, green: paper, blue: paper * 0.97, alpha: 1)
            context.addLines(between: corners)
            context.closePath()
            context.fillPath()

            func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                let top = CGPoint(x: corners[0].x + (corners[1].x - corners[0].x) * u, y: corners[0].y + (corners[1].y - corners[0].y) * u)
                let bottom = CGPoint(x: corners[3].x + (corners[2].x - corners[3].x) * u, y: corners[3].y + (corners[2].y - corners[3].y) * u)
                return CGPoint(x: top.x + (bottom.x - top.x) * v, y: top.y + (bottom.y - top.y) * v)
            }
            context.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            let start: CGFloat = contentAtTop ? 0.08 : 0.55
            for line in 0..<14 {
                let v = start + CGFloat(line) * 0.026
                let end: CGFloat = line % 5 == 4 ? 0.5 : 0.9
                context.addLines(between: [at(0.1, v), at(end, v), at(end, v + 0.012), at(0.1, v + 0.012)])
                context.closePath()
            }
            context.fillPath()
        }
        return CIImage(cgImage: context.makeImage()!)
    }
}

/// An A4 page at about 100 dpi with real text, optionally with a stamp, a shaded header, a picture, a shadow or a rotation.
public struct SyntheticPage {
    public static let size = CGSize(width: 840, height: 1188)
    public static let blockCenter = CGPoint(x: 0.5, y: 0.93)

    public var paper: (CGFloat, CGFloat, CGFloat) = (0.95, 0.95, 0.93)
    public var stamp = false
    public var shadedHeader = false
    public var picture = false
    public var shadow = false
    /// A shadow with sharp edges across the blank top margin, like a hand or a phone.
    public var handShadow = false
    public var rotation: Double = 0

    public init(paper: (CGFloat, CGFloat, CGFloat) = (0.95, 0.95, 0.93), stamp: Bool = false, shadedHeader: Bool = false, picture: Bool = false, shadow: Bool = false, handShadow: Bool = false, rotation: Double = 0) {
        self.paper = paper
        self.stamp = stamp
        self.shadedHeader = shadedHeader
        self.picture = picture
        self.shadow = shadow
        self.handShadow = handShadow
        self.rotation = rotation
    }

    public func render() -> CIImage {
        let size = Self.size
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: paper.0, green: paper.1, blue: paper.2, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        context.saveGState()
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: rotation * .pi / 180)
        context.translateBy(x: -size.width / 2, y: -size.height / 2)

        let words = "The quick brown fox jumps over the lazy dog while the invoice waits for payment".split(separator: " ")
        let font = CTFontCreateWithName("Helvetica" as CFString, 17, nil)
        for line in 0..<30 {
            let start = line * 3 % words.count
            let text = (0..<9).map { String(words[(start + $0) % words.count]) }.joined(separator: " ")
            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.08, alpha: 1)])
            context.textPosition = CGPoint(x: 70, y: size.height - 140 - CGFloat(line) * 30)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.setFillColor(gray: 0.05, alpha: 1)
        context.fill(CGRect(x: 380, y: 60, width: 80, height: 40))
        if shadedHeader {
            context.setFillColor(gray: 0.7, alpha: 1)
            context.fill(CGRect(x: 70, y: size.height - 110, width: 700, height: 28))
        }
        if stamp {
            context.setStrokeColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 1)
            context.setLineWidth(5)
            context.stroke(CGRect(x: 520, y: 120, width: 220, height: 90))
        }
        if picture {
            context.setFillColor(red: 0.2, green: 0.3, blue: 0.25, alpha: 1)
            context.fill(CGRect(x: 120, y: 320, width: 600, height: 420))
        }
        context.restoreGState()

        var image = CIImage(cgImage: context.makeImage()!)
        if shadow {
            let gradient = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: size.width, y: size.height * 0.4),
                "inputColor0": CIColor(red: 0.45, green: 0.45, blue: 0.45), "inputColor1": CIColor(red: 1, green: 1, blue: 1),
            ])!.outputImage!.cropped(to: image.extent)
            image = image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: gradient])
        }
        if handShadow {
            let band = CIImage(color: CIColor(red: 0.62, green: 0.6, blue: 0.58)).cropped(to: CGRect(x: size.width * 0.42, y: 0, width: size.width * 0.16, height: size.height))
            let mask = band.composited(over: CIImage(color: .white).cropped(to: image.extent))
            image = image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        }
        return image
    }
}

extension SyntheticPhoto {
    /// A JPEG photo of a tilted page, as the camera would take it.
    public static func jpeg(page: Quad = Quad(topLeft: CGPoint(x: 0.22, y: 0.18), topRight: CGPoint(x: 0.8, y: 0.21), bottomRight: CGPoint(x: 0.86, y: 0.82), bottomLeft: CGPoint(x: 0.14, y: 0.8))) -> Data {
        CIContext().jpegRepresentation(of: render(page: page), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    }
}

extension Quad {
    public static func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Quad {
        Quad(topLeft: CGPoint(x: x, y: y), topRight: CGPoint(x: x + width, y: y), bottomRight: CGPoint(x: x + width, y: y + height), bottomLeft: CGPoint(x: x, y: y + height))
    }

    public func offset(by d: CGFloat) -> Quad {
        Quad(topLeft: CGPoint(x: topLeft.x + d, y: topLeft.y), topRight: CGPoint(x: topRight.x + d, y: topRight.y), bottomRight: CGPoint(x: bottomRight.x + d, y: bottomRight.y), bottomLeft: CGPoint(x: bottomLeft.x + d, y: bottomLeft.y))
    }
}
