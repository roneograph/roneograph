import CoreGraphics
import Foundation

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

/// Suggests file names from what was read on a page and keeps names valid for file systems and mail apps.
public struct FileNamer: Sendable {
    public static let forbidden = Set("/\\:*?\"<>|")
    public var maximumLength = 80

    public init() {}

    /// Replaces the characters file systems or mail apps reject by a dash, as the user types.
    public func sanitize(_ name: String) -> String {
        var result = String(name.map { Self.forbidden.contains($0) || $0.isNewline ? "-" : $0 }.filter { !$0.unicodeScalars.allSatisfy(\.properties.isDefaultIgnorableCodePoint) })
        while result.hasPrefix(".") { result.removeFirst() }
        return String(result.prefix(maximumLength))
    }

    /// The final name: sanitized, trimmed, never empty.
    public func finalName(_ name: String, fallback: String) -> String {
        let trimmed = sanitize(name).trimmingCharacters(in: .whitespaces).replacing(/\ {2,}/, with: " ")
        return trimmed.isEmpty ? fallback : trimmed
    }

    public func fallback(for date: Date) -> String {
        "Scan \(Self.isoDate(date))"
    }

    /// Up to two names, best first, or the fallback name when the page says nothing useful.
    public func names(for parts: SuggestedParts, date: Date) -> [String] {
        let typeAndIssuer = [parts.type, parts.issuer].compactMap { $0 }.joined(separator: " ")
        let typeAndNumber = parts.type.flatMap { type in parts.number.map { "\(type) \($0)" } }
        let best = parts.issuer == nil ? typeAndNumber ?? parts.type : typeAndIssuer

        var seen = Set<String>()
        let names = [best, typeAndNumber].compactMap { $0 }.map { finalName($0, fallback: "") }.filter { !$0.isEmpty && seen.insert($0).inserted }
        return names.isEmpty ? [fallback(for: date)] : names
    }

    /// "é" becomes "e", "œ" becomes "oe" and "ß" becomes "ss"; other scripts are kept.
    public static func withoutAccents(_ text: String) -> String {
        text.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) ?? text
    }

    public static func isoDate(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}
