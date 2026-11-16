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

/// Names suggested from the text of a page, and the details read on it.
public struct NameSuggestions: Equatable, Sendable {
    public var names: [String]
    public var document: DetectedDocument

    public init(names: [String], document: DetectedDocument = .init()) {
        self.names = names
        self.document = document
    }

    /// Nil when no date was found.
    public var date: Date? { document.details.date }
}

/// Suggests file names from the text of a page and keeps names valid for file systems and mail apps.
public struct FileNamer: Sendable {
    public static let forbidden = Set("/\\:*?\"<>|")
    public var maximumLength = 80
    /// Reads 03/04/2026 as March 4 instead of April 3.
    public var monthFirst: Bool

    public init(monthFirst: Bool = Locale.current.region == .unitedStates) {
        self.monthFirst = monthFirst
    }

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

    /// Up to two names, best first, or the fallback name when the text says nothing useful; `aspectRatio` is the width over the height of the page.
    public func suggestions(lines: [TextLine], date: Date, ownLines: Set<String> = [], aspectRatio: CGFloat? = nil) -> NameSuggestions {
        suggestions(for: DocumentDetector(monthFirst: monthFirst).detect(lines: lines, ownLines: ownLines, aspectRatio: aspectRatio), date: date)
    }

    public func suggestions(for document: DetectedDocument, date: Date) -> NameSuggestions {
        let parts = document.parts
        let typeAndIssuer = [parts.type, parts.issuer].compactMap { $0 }.joined(separator: " ")
        let typeAndNumber = parts.type.flatMap { type in parts.number.map { "\(type) \($0)" } }
        let best = parts.issuer == nil ? typeAndNumber ?? parts.type : typeAndIssuer

        var seen = Set<String>()
        let names = [best, typeAndNumber].compactMap { $0 }.map { finalName($0, fallback: "") }.filter { !$0.isEmpty && seen.insert($0).inserted }
        return NameSuggestions(names: names.isEmpty ? [fallback(for: date)] : names, document: document)
    }

    public static func isoDate(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}
