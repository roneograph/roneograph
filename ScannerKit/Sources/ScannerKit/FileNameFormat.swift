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
        let date = dateSource == .document ? details.date ?? scanDate : scanDate
        if isCustom, let template = try? Template(template) {
            return template.render(name: name, details: details, date: date, scanDate: scanDate, suggestedParts: suggestedParts, format: self)
        }
        return simpleFileName(name: name, date: date)
    }

    /// With dashes or underscores, any run of characters other than letters and digits becomes one separator.
    /// A name that already starts or ends with the date does not get it twice; without a date in the format, it stays where it is.
    private func simpleFileName(name: String, date: Date) -> String {
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
        var words = self.words(rest)
        switch position {
        case .none: break
        case .start: words.insert(stamp, at: 0)
        case .end: words.append(stamp)
        }
        return FileNamer().finalName(words.joined(separator: separator.character), fallback: stamp)
    }

    fileprivate func words(_ text: String) -> [String] {
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

        func render(name: String, details: DocumentDetails, date: Date, scanDate: Date, suggestedParts: SuggestedParts?, format: FileNameFormat) -> String {
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
                var pieces = component.map { token -> String? in
                    switch token {
                    case .text(let text): format.separator == .space ? text : text.replacing(/\s+/, with: format.separator.character)
                    case .variable(let variable): values[variable].flatMap { $0.isEmpty ? nil : $0 }
                    }
                }
                for index in pieces.indices where pieces[index] == nil {
                    if index > 0, let previous = pieces[index - 1], Self.endsWithSeparator(previous) {
                        pieces[index - 1] = previous.replacing(/[\s\-_.]+$/, with: "")
                    } else if index + 1 < pieces.count, let next = pieces[index + 1] {
                        pieces[index + 1] = next.replacing(/^[\s\-_.]+/, with: "")
                    }
                }
                return namer.finalName(pieces.compactMap { $0 }.joined(), fallback: "")
            }
            let folders = rendered.dropLast().filter { !$0.isEmpty }
            return (folders + [namer.finalName(rendered.last ?? "", fallback: iso)]).joined(separator: "/")
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
