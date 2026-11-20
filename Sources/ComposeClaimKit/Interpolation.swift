/// Compose's variable substitution: `$VAR`, `${VAR}`, `${VAR:-default}`, `${VAR-default}`, `${VAR:?message}`,
/// `${VAR?message}`, `${VAR:+alternative}`, `${VAR+alternative}`, and `$$` for a literal `$`. The forms with a
/// colon treat an empty value like an unset one; the forms without it do not.
enum Interpolation {
    enum Failure: Error, Hashable {
        /// `:?` or `?` stopped `docker compose`.
        case required(name: String, message: String)
        /// Text this reader does not follow, such as a lone `$` or an unclosed `${`.
        case malformed
    }

    /// A misreading of the rules, used to name the mistake behind a wrong claim.
    struct Semantics: Hashable {
        var dashCoversEmpty = false
        var colonDashKeepsEmpty = false
        var questionCoversEmpty = false
        var dollarDollarExpands = false
        var dotEnvFirst = false
    }

    struct Result: Hashable {
        var value: String
        /// Names the text used that the conversation does not set; each was taken as unset.
        var unknown: Set<String>
    }

    static func resolve(_ text: String, _ variables: Variables,
                        _ semantics: Semantics = Semantics()) throws(Failure) -> Result {
        var resolver = Resolver(variables: variables, semantics: semantics)
        let value = try resolver.resolve(ArraySlice(text))
        return Result(value: value, unknown: resolver.unknown)
    }

    /// Whether the text holds anything to substitute.
    static func hasVariables(_ text: String) -> Bool {
        text.replacingOccurrences(of: "$$", with: "").contains("$")
    }

    struct Resolver {
        let variables: Variables
        let semantics: Semantics
        var unknown: Set<String> = []

        mutating func resolve(_ characters: ArraySlice<Character>) throws(Failure) -> String {
            var output = ""
            var rest = characters
            while let character = rest.popFirst() {
                guard character == "$" else {
                    output.append(character)
                    continue
                }
                guard let next = rest.first else { throw .malformed }
                if next == "$" {
                    rest.removeFirst()
                    if semantics.dollarDollarExpands { rest.insert("$", at: rest.startIndex) } else { output += "$" }
                } else if next == "{" {
                    rest.removeFirst()
                    output += try braced(&rest)
                } else if Names.isNameCharacter(next), !next.isNumber {
                    let name = String(rest.prefix(while: Names.isNameCharacter))
                    rest.removeFirst(name.count)
                    output += lookup(name) ?? ""
                } else {
                    throw .malformed
                }
            }
            return output
        }

        mutating func lookup(_ name: String) -> String? {
            if !variables.knows(name) { unknown.insert(name) }
            return variables.unread.contains(name) ? nil : variables.value(name, dotEnvFirst: semantics.dotEnvFirst)
        }

        /// After `${`: the name, an operator and its word, up to the matching `}`.
        mutating func braced(_ rest: inout ArraySlice<Character>) throws(Failure) -> String {
            let name = String(rest.prefix(while: Names.isNameCharacter))
            guard Names.isName(name) else { throw .malformed }
            rest.removeFirst(name.count)
            var operation = ""
            while let character = rest.first, ":-?+".contains(character), operation.count < 2 {
                operation.append(rest.removeFirst())
            }
            var depth = 0
            var word: [Character] = []
            while true {
                guard let character = rest.popFirst() else { throw .malformed }
                if character == "}", depth == 0 { break }
                if character == "{", word.last == "$" { depth += 1 }
                if character == "}" { depth -= 1 }
                word.append(character)
            }
            return try apply(operation, name: name, word: ArraySlice(word))
        }

        mutating func apply(_ operation: String, name: String, word: ArraySlice<Character>) throws(Failure) -> String {
            let value = lookup(name)
            let isEmpty = value?.isEmpty ?? true
            switch operation {
            case "" where word.isEmpty:
                return value ?? ""
            case ":-":
                if let value, !(isEmpty && !semantics.colonDashKeepsEmpty) { return value }
                return try resolve(word)
            case "-":
                if let value, !(isEmpty && semantics.dashCoversEmpty) { return value }
                return try resolve(word)
            case ":?", "?":
                guard let value, !(isEmpty && (operation == ":?" || semantics.questionCoversEmpty)) else {
                    throw .required(name: name, message: try resolve(word))
                }
                return value
            case ":+":
                return isEmpty ? "" : try resolve(word)
            case "+":
                return value == nil ? "" : try resolve(word)
            default:
                throw .malformed
            }
        }
    }
}
