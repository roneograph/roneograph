import Foundation

/// Turns the name and details of a scan into its file name: "Lumen Energy invoice" can become "2026-11-12-lumen-energy-invoice",
/// or "Invoice/2026-11 Lumen Energy" with a custom format.
public struct FileNameFormat: Equatable, Sendable, Codable {
    public enum Separator: String, Equatable, Sendable, Codable, CaseIterable {
        case space, dash, underscore

        public var character: String {
            switch self {
            case .space: " "
            case .dash: "-"
            case .underscore: "_"
            }
        }
    }

    public enum DatePosition: String, Equatable, Sendable, Codable, CaseIterable {
        case none, start, end
    }

    public enum DateStyle: String, Equatable, Sendable, Codable, CaseIterable {
        /// 2026-11-12
        case day
        /// 20261112
        case compactDay
        /// 2026-11
        case month

        public func format(_ date: Date) -> String {
            let iso = FileNamer.isoDate(date)
            switch self {
            case .day: return iso
            case .compactDay: return iso.replacing("-", with: "")
            case .month: return String(iso.prefix(7))
            }
        }
    }

    public enum DateSource: String, Equatable, Sendable, Codable, CaseIterable {
        /// The date printed on the document, or the day of the scan when none was found.
        case document
        case scan
    }

    public static let defaultTemplate = "{YYYY}-{MM}-{DD} {NAME}"

    public var datePosition: DatePosition
    public var dateStyle: DateStyle
    public var dateSource: DateSource
    public var separator: Separator
    public var lowercase: Bool
    /// Uses `template` instead of the date position and style.
    public var isCustom: Bool
    /// Always a valid template; kept when the custom format is turned off.
    public var template: String

    public init(datePosition: DatePosition = .none, dateStyle: DateStyle = .day, dateSource: DateSource = .document, separator: Separator = .space, lowercase: Bool = false, isCustom: Bool = false, template: String = Self.defaultTemplate) {
        self.datePosition = datePosition
        self.dateStyle = dateStyle
        self.dateSource = dateSource
        self.separator = separator
        self.lowercase = lowercase
        self.isCustom = isCustom
        self.template = template
    }

    private enum CodingKeys: String, CodingKey {
        case datePosition, dateStyle, dateSource, separator, lowercase, isCustom, template, datePrefix
    }

    /// Missing, unknown or invalid values keep their default; the former "date first" switch becomes a date at the start.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        if let position = try? container.decode(DatePosition.self, forKey: .datePosition) {
            datePosition = position
        } else if (try? container.decode(Bool.self, forKey: .datePrefix)) == true {
            datePosition = .start
        }
        dateStyle = (try? container.decode(DateStyle.self, forKey: .dateStyle)) ?? dateStyle
        dateSource = (try? container.decode(DateSource.self, forKey: .dateSource)) ?? dateSource
        separator = (try? container.decode(Separator.self, forKey: .separator)) ?? separator
        lowercase = (try? container.decode(Bool.self, forKey: .lowercase)) ?? lowercase
        if let template = try? container.decode(String.self, forKey: .template), (try? Template(template)) != nil {
            self.template = template
            isCustom = (try? container.decode(Bool.self, forKey: .isCustom)) ?? isCustom
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(datePosition, forKey: .datePosition)
        try container.encode(dateStyle, forKey: .dateStyle)
        try container.encode(dateSource, forKey: .dateSource)
        try container.encode(separator, forKey: .separator)
        try container.encode(lowercase, forKey: .lowercase)
        try container.encode(isCustom, forKey: .isCustom)
        try container.encode(template, forKey: .template)
    }

    /// The file name, with folders separated by "/" when a custom format has them.
    /// `suggestedParts` is nil for a name the user typed: a custom format then keeps it as typed instead of leaving out what it already shows.
    public func fileName(name: String, details: DocumentDetails = .init(), scanDate: Date, suggestedParts: SuggestedParts? = nil) -> String {
        segments(name: name, details: details, scanDate: scanDate, suggestedParts: suggestedParts).map(\.text).joined()
    }

    /// The file name split by where each part comes from, to show how it is built.
    /// A custom format whose name adds nothing keeps an empty name segment where the name would go.
    public func segments(name: String, details: DocumentDetails = .init(), scanDate: Date, suggestedParts: SuggestedParts? = nil) -> [FileNameSegment] {
        let date = dateSource == .document ? details.date ?? scanDate : scanDate
        if isCustom, let template = try? Template(template) {
            return template.render(name: name, details: details, date: date, scanDate: scanDate, suggestedParts: suggestedParts, format: self)
        }
        return simpleSegments(name: name, date: date)
    }

    /// With dashes or underscores, any run of characters other than letters and digits becomes one separator.
    /// A name that already starts or ends with the date does not get it twice; without a date in the format, it stays where it is.
    private func simpleSegments(name: String, date: Date) -> [FileNameSegment] {
        let stamp = dateStyle.format(date)
        var rest = name.trimmingCharacters(in: .whitespaces)
        var position = datePosition
        for written in Set([stamp, FileNamer.isoDate(date)]) {
            if rest.hasPrefix(written) {
                rest = String(rest.dropFirst(written.count))
                if position == .none { position = .start }
            } else if rest.hasSuffix(written) {
                rest = String(rest.dropLast(written.count))
                if position == .none { position = .end }
            }
        }
        let name = FileNameSegment(words(rest).joined(separator: separator.character), .name)
        let dated = FileNameSegment(stamp, .date)
        let separator = FileNameSegment(separator.character, .text)
        guard !name.text.isEmpty else { return [dated] }
        let segments = switch position {
        case .none: [name]
        case .start: [dated, separator, name]
        case .end: [name, separator, dated]
        }
        return FileNameSegment.finalized(segments, fallback: stamp)
    }

    fileprivate func words(_ text: String) -> [String] {
        let text = FileNamer.withoutAccents(text)
        let words = separator == .space
            ? text.split(whereSeparator: \.isWhitespace).map(String.init)
            : text.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        return lowercase ? words.map { $0.lowercased() } : words
    }
}

extension FileNameFormat {
    /// A custom format such as "{CATEGORY}/{YYYY}-{MM} {ISSUER}": text, variables in braces, and "/" between folders.
    public struct Template: Equatable, Sendable {
        public enum Variable: String, CaseIterable, Sendable {
            case name = "NAME"
            case year = "YYYY"
            case shortYear = "YY"
            case month = "MM"
            case day = "DD"
            case category = "CATEGORY"
            case issuer = "ISSUER"
            case number = "NUMBER"

            public var placeholder: String { "{\(rawValue)}" }

            var source: FileNameSegment.Source {
                switch self {
                case .name: .name
                case .year, .shortYear, .month, .day: .date
                case .category: .category
                case .issuer: .issuer
                case .number: .number
                }
            }
        }

        public enum Token: Equatable, Sendable {
            case text(String)
            case variable(Variable)
        }

        public enum ParseError: Error, Equatable {
            case empty
            case unknownVariable(String)
            case unclosedBrace
            case forbiddenCharacter(Character)
            case emptyFolder
            case relativeFolder

            public var message: String {
                switch self {
                case .empty: "The format is empty."
                case .unknownVariable(let name): "{\(name)} is not a variable."
                case .unclosedBrace: "A { is not closed."
                case .forbiddenCharacter(let character): "File names cannot contain \(character)."
                case .emptyFolder: "A folder name is empty."
                case .relativeFolder: "Folders cannot be named . or .."
                }
            }
        }

        /// The folders, then the file name.
        public let components: [[Token]]

        public init(_ string: String) throws(ParseError) {
            let string = string.hasSuffix(".pdf") ? String(string.dropLast(4)) : string
            guard !string.trimmingCharacters(in: .whitespaces).isEmpty else { throw .empty }
            components = try string.split(separator: "/", omittingEmptySubsequences: false).map { component throws(ParseError) in
                let trimmed = component.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { throw .emptyFolder }
                guard trimmed != ".", trimmed != ".." else { throw .relativeFolder }
                return try Self.tokens(component)
            }
        }

        public var variables: Set<Variable> {
            Set(components.joined().compactMap { if case .variable(let variable) = $0 { variable } else { nil } })
        }

        private static func tokens(_ component: Substring) throws(ParseError) -> [Token] {
            var tokens: [Token] = []
            var rest = component
            while !rest.isEmpty {
                if rest.first == "{" {
                    guard let close = rest.firstIndex(of: "}") else { throw .unclosedBrace }
                    let name = String(rest[rest.index(after: rest.startIndex)..<close])
                    guard let variable = Variable(rawValue: name) else { throw .unknownVariable(name) }
                    tokens.append(.variable(variable))
                    rest = rest[rest.index(after: close)...]
                } else {
                    let end = rest.firstIndex(of: "{") ?? rest.endIndex
                    let text = String(rest[..<end])
                    if let forbidden = text.first(where: { FileNamer.forbidden.contains($0) || $0 == "}" }) { throw .forbiddenCharacter(forbidden) }
                    tokens.append(.text(text))
                    rest = rest[end...]
                }
            }
            return tokens
        }

        func render(name: String, details: DocumentDetails, date: Date, scanDate: Date, suggestedParts: SuggestedParts?, format: FileNameFormat) -> [FileNameSegment] {
            let iso = FileNamer.isoDate(date)
            let namer = FileNamer()
            let values: [Variable: String] = [
                .name: suggestedParts.map { strip($0, dates: [date, scanDate], from: name) } ?? name,
                .year: String(iso.prefix(4)),
                .shortYear: String(iso.dropFirst(2).prefix(2)),
                .month: String(iso.dropFirst(5).prefix(2)),
                .day: String(iso.suffix(2)),
                .category: details.category.rawValue,
                .issuer: details.issuer ?? "",
                .number: details.number ?? "",
            ].mapValues { format.words(namer.sanitize($0)).joined(separator: format.separator.character) }

            let rendered = components.map { component in
                var pieces = component.map { token -> (text: String?, source: FileNameSegment.Source) in
                    switch token {
                    case .text(let text): (FileNamer.withoutAccents(format.separator == .space ? text : text.replacing(/\s+/, with: format.separator.character)), .text)
                    case .variable(let variable): (values[variable].flatMap { $0.isEmpty ? nil : $0 }, variable.source)
                    }
                }
                for index in pieces.indices where pieces[index].text == nil {
                    if index > 0, let previous = pieces[index - 1].text, Self.endsWithSeparator(previous) {
                        pieces[index - 1].text = previous.replacing(/[\s\-_.]+$/, with: "")
                    } else if index + 1 < pieces.count, let next = pieces[index + 1].text {
                        pieces[index + 1].text = next.replacing(/^[\s\-_.]+/, with: "")
                    }
                }
                let segments = pieces.compactMap { piece -> FileNameSegment? in
                    guard let text = piece.text, !text.isEmpty else { return piece.source == .name ? FileNameSegment("", .name) : nil }
                    return FileNameSegment(text, piece.source)
                }
                return FileNameSegment.finalized(segments, fallback: "")
            }
            var file = rendered.last ?? []
            if file.allSatisfy(\.text.isEmpty) { file = [FileNameSegment(iso, .date)] + file.filter { $0.source == .name } }
            let folders = rendered.dropLast().filter { !$0.allSatisfy(\.text.isEmpty) }
            return (folders + [file]).flatMap { $0 + [FileNameSegment("/", .folderSeparator)] }.dropLast()
        }

        private static func endsWithSeparator(_ text: String) -> Bool {
            text.last.map { $0.isWhitespace || "-_.".contains($0) } ?? false
        }

        /// Leaves out of a suggested name what the format already shows.
        private func strip(_ parts: SuggestedParts, dates: [Date], from name: String) -> String {
            let variables = variables
            var shown: [String] = []
            if variables.contains(.category), let type = parts.type { shown.append(type) }
            if variables.contains(.issuer), let issuer = parts.issuer { shown.append(issuer) }
            if variables.contains(.number), let number = parts.number { shown.append(number) }
            if !variables.isDisjoint(with: [.year, .shortYear, .month, .day]) { shown += dates.map(FileNamer.isoDate) }
            var result = name
            for part in shown.map({ FileNamer().sanitize($0) }) where !part.isEmpty {
                result = result.replacingOccurrences(of: part, with: " ", options: .caseInsensitive)
            }
            return result.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        }
    }
}

/// A part of a file name and where it comes from.
public struct FileNameSegment: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case text, folderSeparator, name, date, category, issuer, number
    }

    public var text: String
    public var source: Source

    public init(_ text: String, _ source: Source) {
        self.text = text
        self.source = source
    }

    /// Trims the ends as final file names are; anything else the file name rules change makes one plain segment of the final name.
    static func finalized(_ segments: [FileNameSegment], fallback: String) -> [FileNameSegment] {
        var segments = segments
        if let first = segments.firstIndex(where: { !$0.text.isEmpty }) {
            segments[first].text = String(segments[first].text.drop(while: \.isWhitespace))
        }
        if let last = segments.lastIndex(where: { !$0.text.isEmpty }) {
            segments[last].text = String(segments[last].text.reversed().drop(while: \.isWhitespace).reversed())
        }
        let joined = segments.map(\.text).joined()
        let final = FileNamer().finalName(joined, fallback: fallback)
        return final == joined ? segments : [FileNameSegment(final, .text)]
    }
}
