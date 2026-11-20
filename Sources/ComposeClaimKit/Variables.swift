/// The variables compose substitutes into a compose file: the shell's environment, then the `.env` file next to the
/// compose file. The shell wins.
public struct Variables: Sendable, Hashable {
    /// Exported in the shell that runs `docker compose`.
    public var shell: [String: String]
    /// Set in the project's `.env` file.
    public var dotEnv: [String: String]
    /// Set in `.env` in a way this reader does not follow (a `$` in the value, an unclosed quote).
    public var unread: Set<String>
    /// Said to be unset ("when `TAG` is unset").
    public var unset: Set<String>

    public init(shell: [String: String] = [:], dotEnv: [String: String] = [:], unread: Set<String> = [],
                unset: Set<String> = []) {
        self.shell = shell
        self.dotEnv = dotEnv
        self.unread = unread
        self.unset = unset
    }

    /// Whether the conversation shows a value (or an empty value) for the name, or says it is unset.
    func knows(_ name: String) -> Bool {
        unset.contains(name) || shell[name] != nil || (dotEnv[name] != nil && !unread.contains(name))
    }

    func value(_ name: String, dotEnvFirst: Bool) -> String? {
        if unset.contains(name) { return nil }
        return dotEnvFirst ? dotEnv[name] ?? shell[name] : shell[name] ?? dotEnv[name]
    }
}

/// Reads a `.env` file the way compose does in the cases probed against `docker compose config`: `#` lines and a
/// ` #` after an unquoted value are comments, `export ` is dropped, spaces around an unquoted value go, single
/// quotes keep everything literal, double quotes keep `#` and turn `\n` into a newline.
enum EnvFile {
    static func parse(_ lines: [String]) -> (values: [String: String], unread: Set<String>) {
        var values: [String: String] = [:]
        var unread: Set<String> = []
        for raw in lines {
            var line = raw.trimmed
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmed }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = String(line[..<equals]).trimmed
            guard Names.isName(name) else { continue }
            if let value = value(String(line[line.index(after: equals)...]).trimmed) {
                values[name] = value
            } else {
                unread.insert(name)
                values[name] = ""
            }
        }
        return (values, unread)
    }

    /// The value, or `nil` when this reader does not follow it.
    static func value(_ text: String) -> String? {
        if text.hasPrefix("'") {
            guard text.count >= 2, text.hasSuffix("'") else { return nil }
            return String(text.dropFirst().dropLast())
        }
        if text.hasPrefix("\"") {
            guard text.count >= 2, text.hasSuffix("\""), !text.contains("$") else { return nil }
            return String(text.dropFirst().dropLast()).replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
        }
        let kept = text.range(of: " #").map { String(text[..<$0.lowerBound]) } ?? text
        return kept.contains("$") ? nil : kept.trimmed
    }
}

enum Names {
    static func isName(_ text: String) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy(isNameCharacter)
    }

    static func isNameCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_")
    }
}
