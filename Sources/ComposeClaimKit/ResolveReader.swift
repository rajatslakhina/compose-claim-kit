/// "With `TAG` unset, `${TAG:-latest}` becomes `latest`": an expression in inline code, a verb, and the value (or
/// the error) the answer says it gives, under the condition the sentence states.
enum ResolveReader {
    static let verbs = ["becomes", "resolves to", "expands to", "evaluates to", "gives you", "gives",
                        "is replaced with", "is replaced by", "turns into", "yields", "will be", "is substituted with",
                        "produces", "comes out as", "ends up as", "is"]
    static let failures = ["fails", "errors", "errors out", "stops with an error", "aborts", "exits with an error",
                           "refuses to start", "throws an error", "raises an error"]
    static let empties = ["an empty string", "empty string", "empty", "blank", "nothing"]

    static func claims(_ sentence: String, scene: Scene) -> [ComposeClaim] {
        let pieces = Sentences.pieces(sentence)
        var claims: [ComposeClaim] = []
        for (index, piece) in pieces.enumerated() where piece.isCode && Interpolation.hasVariables(piece.text) {
            guard index + 1 < pieces.count else { continue }
            let after = spaced(pieces[index + 1].text)
            guard let claimed = claimed(after: after, next: index + 2 < pieces.count ? pieces[index + 2].text : nil)
            else { continue }
            let resolves = ComposeClaim.Resolves(expression: piece.text, condition: condition(pieces, skipping: index),
                                                 claimed: claimed)
            claims.append(ComposeClaim(subject: .resolves(resolves), sentence: sentence, scene: scene))
        }
        return claims
    }

    /// The outcome the prose right after the expression states: a failure verb, a verb and an empty value, or a
    /// verb followed directly by a code span.
    static func claimed(after prose: String, next code: String?) -> ResolveOutcome? {
        if failures.contains(where: { prose.hasPrefix(" " + $0 + " ") }) { return .failure }
        for verb in verbs {
            guard prose.hasPrefix(" " + verb + " ") else { continue }
            let rest = String(prose.dropFirst(verb.count + 2))
            if empties.contains(where: { rest.hasPrefix($0 + " ") || rest == $0 + " " }) { return .value("") }
            if let code, rest.trimmed.isEmpty { return .value(code) }
            return nil
        }
        return nil
    }

    /// The prose folded, with punctuation as space and a space at each end.
    static func spaced(_ text: String) -> String {
        let plain = String(text.folded.map { ",;:!?().".contains($0) ? " " : $0 })
        return " " + plain.split(separator: " ").joined(separator: " ") + " "
    }

    /// "when `TAG` is unset", "if `TAG` is empty", "with `TAG=1.2`", "when `TAG` is set to `1.2`".
    static func condition(_ pieces: [(text: String, isCode: Bool)], skipping expression: Int)
        -> ResolveCondition? {
        for (index, piece) in pieces.enumerated() where piece.isCode && index != expression {
            let code = piece.text.trimmed
            if let equals = code.firstIndex(of: "="), Names.isName(String(code[..<equals])) {
                let name = String(code[..<equals])
                let value = String(code[code.index(after: equals)...])
                return value.isEmpty ? .empty(name) : .set(name, value)
            }
            guard Names.isName(code), index + 1 < pieces.count else { continue }
            let after = spaced(pieces[index + 1].text)
            let unset = [" is unset ", " is not set ", " isn't set ", " is undefined ", " is missing ", " unset ",
                         " is not defined "]
            let empty = [" is empty ", " is blank ", " is set to an empty string ", " is set but empty ",
                         " is an empty string ", " empty ", " set to an empty string "]
            if unset.contains(where: after.hasPrefix) { return .unset(code) }
            if empty.contains(where: after.hasPrefix) { return .empty(code) }
            if [" is set to ", " set to ", " is "].contains(where: { after == $0 }), index + 2 < pieces.count {
                return .set(code, pieces[index + 2].text)
            }
        }
        return nil
    }
}
