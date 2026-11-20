/// Reads the YAML a compose file is usually written in: block mappings and sequences, flow sequences of scalars,
/// quoted and plain scalars, comments. Anything else (anchors, aliases, `<<` merges, tags, block scalars, flow
/// mappings, several documents, values continued on the next line) is refused with a reason, so a file this reader
/// does not follow makes its claims unchecked instead of misread.
enum ComposeYAML {
    struct Unsupported: Error, Equatable {
        let reason: String
    }

    struct Line: Equatable {
        let number: Int
        let indent: Int
        let text: String
    }

    static func parse(_ source: String) throws(Unsupported) -> ComposeNode {
        var lines: [Line] = []
        for (offset, raw) in source.components(separatedBy: "\n").enumerated() {
            let content = stripComment(raw)
            let indent = content.prefix { $0 == " " }.count
            let rest = content.dropFirst(indent)
            let text = rest.trimmed
            if text.isEmpty { continue }
            if rest.first == "\t" { throw Unsupported(reason: "tabs in the indentation (line \(offset + 1))") }
            if text == "---", lines.isEmpty { continue }
            if text == "---" || text == "..." || text.hasPrefix("%") {
                throw Unsupported(reason: "several YAML documents or a directive (line \(offset + 1))")
            }
            lines.append(Line(number: offset + 1, indent: indent, text: text))
        }
        guard let first = lines.first else { return .null }
        var parser = Parser(lines: lines)
        let node = try parser.block(indent: first.indent)
        if parser.index < lines.count {
            throw Unsupported(reason: "indentation this reader does not follow (line \(lines[parser.index].number))")
        }
        return node
    }

    /// The line without its comment: a `#` at the start or after a space, outside a quoted scalar.
    static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character?
        var output = ""
        var characters = Array(line)[...]
        while let character = characters.popFirst() {
            if let open = quote {
                if character == open, open == "'", characters.first == "'" {
                    output.append(character)
                    output.append(characters.removeFirst())
                    continue
                }
                if character == "\\", open == "\"", let escaped = characters.popFirst() {
                    output.append(character)
                    output.append(escaped)
                    continue
                }
                if character == open { quote = nil }
            } else if character == "#", previous == nil || previous?.isWhitespace == true {
                break
            } else if character == "\"" || character == "'", opensQuote(output) {
                quote = character
            }
            output.append(character)
            previous = character
        }
        return output
    }

    /// A quote opens a scalar only where one starts: at the line's start, after `key: `, `- `, `[` or `,`.
    static func opensQuote(_ before: String) -> Bool {
        let kept = before.trimmed
        guard let last = kept.last else { return true }
        if last == "[" || last == "," { return true }
        return (last == ":" || last == "-") && before.last?.isWhitespace == true
    }

    struct Parser {
        var lines: [Line]
        var index = 0

        mutating func block(indent: Int) throws(Unsupported) -> ComposeNode {
            isItem(lines[index].text) ? try sequence(indent: indent) : try mapping(indent: indent)
        }

        func isItem(_ text: String) -> Bool {
            text == "-" || text.hasPrefix("- ")
        }

        mutating func sequence(indent: Int) throws(Unsupported) -> ComposeNode {
            var items: [ComposeNode] = []
            while index < lines.count, lines[index].indent == indent, isItem(lines[index].text) {
                let line = lines[index]
                let afterDash = line.text.dropFirst()
                let rest = afterDash.trimmed
                if rest.isEmpty {
                    index += 1
                    items.append(try nested(after: indent, sameIndentSequence: false))
                } else if ComposeYAML.key(rest) != nil {
                    // "- key: value": a mapping whose first key sits where the text after the dash starts.
                    let column = indent + 1 + afterDash.prefix { $0 == " " }.count
                    lines[index] = Line(number: line.number, indent: column, text: rest)
                    items.append(try mapping(indent: column))
                } else {
                    index += 1
                    items.append(try ComposeYAML.value(rest, line: line.number))
                    try noContinuation(deeperThan: indent)
                }
            }
            return .list(items)
        }

        mutating func mapping(indent: Int) throws(Unsupported) -> ComposeNode {
            var entries: [ComposeEntry] = []
            while index < lines.count, lines[index].indent == indent {
                let line = lines[index]
                guard !isItem(line.text), let (key, rest) = ComposeYAML.key(line.text) else {
                    throw Unsupported(reason: "a line that is not `key: value` (line \(line.number))")
                }
                if key == "<<" { throw Unsupported(reason: "a `<<` merge key (line \(line.number))") }
                index += 1
                if rest.isEmpty {
                    entries.append(ComposeEntry(key: key, value: try nested(after: indent, sameIndentSequence: true)))
                } else {
                    entries.append(ComposeEntry(key: key, value: try ComposeYAML.value(rest, line: line.number)))
                    try noContinuation(deeperThan: indent)
                }
            }
            return .map(entries)
        }

        /// The block under a key or a bare dash. Under a key, a sequence may sit at the key's own indentation.
        mutating func nested(after indent: Int, sameIndentSequence: Bool) throws(Unsupported) -> ComposeNode {
            guard index < lines.count else { return .null }
            let next = lines[index]
            if next.indent > indent { return try block(indent: next.indent) }
            if sameIndentSequence, next.indent == indent, isItem(next.text) { return try sequence(indent: indent) }
            return .null
        }

        func noContinuation(deeperThan indent: Int) throws(Unsupported) {
            if index < lines.count, lines[index].indent > indent {
                throw Unsupported(reason: "a value continued on the next line (line \(lines[index].number))")
            }
        }
    }

    /// The key and the rest of a `key: value` line, or `nil` when the text is a plain value.
    static func key(_ text: String) -> (String, String)? {
        if let open = text.first, open == "\"" || open == "'" {
            guard let (key, end) = quoted(text), text[end...].hasPrefix(":") else { return nil }
            let rest = text[text.index(after: end)...]
            guard rest.isEmpty || rest.first == " " else { return nil }
            return (key, rest.trimmed)
        }
        guard let first = text.first, !"[{&*!|>%@`".contains(first) else { return nil }
        if text.hasSuffix(":"), !text.dropLast().contains(": ") { return (String(text.dropLast()).trimmed, "") }
        guard let colon = text.range(of: ": ") else { return nil }
        return (String(text[..<colon.lowerBound]).trimmed, String(text[colon.upperBound...]).trimmed)
    }

    /// A quoted scalar at the start of the text, and the index just after its closing quote.
    static func quoted(_ text: String) -> (String, String.Index)? {
        guard let open = text.first else { return nil }
        var value = ""
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == open {
                guard open == "'", next < text.endIndex, text[next] == "'" else { return (value, next) }
                value.append("'")
                index = text.index(after: next)
                continue
            }
            if character == "\\", open == "\"", next < text.endIndex {
                value.append(escape(text[next]))
                index = text.index(after: next)
                continue
            }
            value.append(character)
            index = next
        }
        return nil
    }

    static func escape(_ character: Character) -> Character {
        switch character {
        case "n": "\n"
        case "t": "\t"
        default: character
        }
    }

    /// A value written after `key: ` or `- `.
    static func value(_ text: String, line: Int) throws(Unsupported) -> ComposeNode {
        let unsupported: [(Character, String)] = [("&", "an anchor"), ("*", "an alias"), ("!", "a tag"),
                                                  ("|", "a block scalar"), (">", "a block scalar"),
                                                  ("{", "a flow mapping")]
        if let first = text.first, let (_, what) = unsupported.first(where: { $0.0 == first }) {
            throw Unsupported(reason: "\(what) (line \(line))")
        }
        if text.hasPrefix("[") { return try flow(text, line: line) }
        if text.first == "\"" || text.first == "'" {
            guard let (value, end) = quoted(text), end == text.endIndex else {
                throw Unsupported(reason: "a quoted value this reader does not follow (line \(line))")
            }
            return .scalar(value)
        }
        if ["~", "null", "Null", "NULL"].contains(text) { return .null }
        if text.contains(": ") { throw Unsupported(reason: "a mapping inside a plain value (line \(line))") }
        return .scalar(text)
    }

    /// `[80, "443", 'x']`: a flow sequence of scalars on one line.
    static func flow(_ text: String, line: Int) throws(Unsupported) -> ComposeNode {
        guard text.hasSuffix("]"), text.count >= 2 else {
            throw Unsupported(reason: "a flow sequence over several lines (line \(line))")
        }
        let inside = text.dropFirst().dropLast()
        var items: [String] = []
        var current = ""
        var quote: Character?
        for character in inside {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "," {
                items.append(current)
                current = ""
                continue
            } else if "[]{}".contains(character) {
                throw Unsupported(reason: "a nested flow collection (line \(line))")
            }
            current.append(character)
        }
        items.append(current)
        let trimmed = items.map(\.trimmed)
        if trimmed == [""] { return .list([]) }
        var nodes: [ComposeNode] = []
        for item in trimmed where !item.isEmpty {
            nodes.append(try value(item, line: line))
        }
        return .list(nodes)
    }
}
