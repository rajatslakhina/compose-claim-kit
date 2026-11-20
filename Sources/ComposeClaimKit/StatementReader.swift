/// General statements about compose, read from sentences that name what they are about (`depends_on`, `.env`,
/// `env_file`, `expose`, a port mapping, `localhost`). A negation right before the verb turns a wrong statement
/// into its correct counterpart ("`depends_on` does not wait for the database to be ready").
enum StatementReader {
    typealias Statement = ComposeClaim.Statement

    /// Hedged, conditional or reported sentences make no statement.
    static let blockers = ["would", "could", "might", "unless", "mistake", "misconception", "myth", "wrongly",
                           "incorrectly", "people think", "assume", "assumes", "assuming", "kubernetes", "k8s",
                           "github actions", "if you"]
    static let negators = ["not", "never", "doesn't", "does not", "don't", "won't", "isn't", "aren't", "only",
                           "cannot", "can't"]

    /// Negations that rule a sentence out unless they are the one right before the verb.
    static let strongNegators = ["not", "never", "cannot", "instead of", "rather than", "no longer"]

    /// Each clause (split at `;` and "but") is read on its own; every rule wants its topic before its verb in the
    /// same clause, and a negation anywhere but right before that verb means no statement.
    static func statements(in sentence: String) -> [Statement] {
        let raw = sentence.folded
        guard !Words.containsAny(normalized(raw), blockers) else { return [] }
        let negations = negationCount(normalized(raw))
        var found: [Statement] = []
        for clause in raw.replacingOccurrences(of: " but ", with: ";").split(separator: ";").map(String.init) {
            let text = normalized(clause)
            found += dependsOn(text, negations)
            found += dotEnv(text, negations)
            found += precedence(text, negations)
            found += expose(clause, text, negations)
            if negations == 0 {
                found += binding(clause, text)
                found += order(text)
            }
            found += localhost(text, negations)
        }
        return found
    }

    /// Backticks dropped, punctuation as space, a space at each end. A full stop goes only where it ends a word, so
    /// `.env` keeps its dot.
    static func normalized(_ text: String) -> String {
        (" " + String(text.replacingOccurrences(of: "`", with: "").map {
            ",;!?()\"".contains($0) ? " " : $0
        }) + " ").replacingOccurrences(of: ". ", with: " ")
    }

    static func negationCount(_ text: String) -> Int {
        let words = strongNegators.reduce(0) { $0 + StatementReader.ranges(of: " " + $1 + " ", in: text).count }
        return words + ranges(of: "n't", in: text).count
    }

    /// Whether the first of the verbs is negated, or `nil` when no verb follows a topic in the clause or the
    /// sentence holds a negation elsewhere.
    static func polarity(_ text: String, topics: [String], verbs: [String], negations: Int) -> Bool? {
        let hits = verbs.compactMap { text.range(of: " " + $0 + " ") }
        guard let verb = hits.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let before = String(text[..<verb.lowerBound])
        guard topics.contains(where: before.contains) else { return nil }
        let near = " " + before.split(separator: " ").suffix(3).joined(separator: " ") + " "
        guard negations == negationCount(near) else { return nil }
        return isNegated(before)
    }

    /// Whether the last three words of the text hold a negator.
    static func isNegated(_ before: String) -> Bool {
        let words = before.split(separator: " ").suffix(3).joined(separator: " ")
        return negators.contains { Words.contains(" " + words + " ", $0) } || words.hasSuffix("n't")
    }

    static func dependsOn(_ text: String, _ negations: Int) -> [Statement] {
        guard text.contains("depends_on") || text.contains("depends on"),
              !Words.containsAny(text, ["condition", "service_healthy", "healthcheck", "health check", "healthy",
                                        "service_completed_successfully"]),
              Words.containsAny(text, ["ready", "readiness", "accepting connections", "up and running",
                                       "fully started", "initialized", "initialised"]) else { return [] }
        let verbs = ["wait", "waits", "waiting", "guarantee", "guarantees", "ensure", "ensures", "make sure",
                     "makes sure", "wait for", "waits for", "waits until"]
        let topics = ["depends_on", "depends on"]
        guard let negated = polarity(text, topics: topics, verbs: verbs, negations: negations) else { return [] }
        return [negated ? .dependsOnOrdersStart : .dependsOnWaitsForReady]
    }

    static func dotEnv(_ text: String, _ negations: Int) -> [Statement] {
        guard text.contains(" .env "), !text.contains("env_file"), !text.contains("--env-file") else { return [] }
        if Words.containsAny(text, ["substitution", "interpolation", "substitute", "interpolate"]),
           Words.containsAny(text, ["only", "used for", "is for", "used to"]),
           !Words.containsAny(text, ["container", "containers"]) || Words.containsAny(text, ["not", "n't"]) {
            return [.dotEnvForSubstitution]
        }
        guard Words.containsAny(text, ["container", "containers", "inside the app", "your app's process"]) else {
            return []
        }
        let verbs = ["available", "passed", "passes", "pass", "injected", "injects", "visible", "loaded", "reach",
                     "reaches", "end up", "ends up", "become", "becomes", "sent", "exported", "copied"]
        let topics = [".env", "compose"]
        guard let negated = polarity(text, topics: topics, verbs: verbs, negations: negations) else { return [] }
        return [negated ? .dotEnvForSubstitution : .dotEnvReachesContainer]
    }

    static let winVerbs = ["overrides", "override", "takes precedence over", "take precedence over", "wins over",
                           "win over", "beats", "beat", "has priority over", "takes priority over",
                           "has precedence over", "is preferred over", "trumps", "replaces"]
    static let loseVerbs = ["is overridden by", "are overridden by", "loses to", "lose to", "is replaced by",
                            "are replaced by"]

    /// Who wins between two sources: the one before an active verb, or the one after a passive verb.
    static func precedence(_ text: String, _ negations: Int) -> [Statement] {
        var found: [Statement] = []
        if text.contains(" .env "), Words.containsAny(text, ["shell", "exported", "export", "your environment"]) {
            found += winner(text, first: [".env"], second: ["shell", "exported", "export", "your environment"],
                            firstWins: .dotEnvBeatsShell, secondWins: .shellBeatsDotEnv, negations: negations)
        }
        if text.contains("env_file"), text.contains("environment") {
            found += winner(text, first: ["env_file"], second: ["environment"],
                            firstWins: .envFileBeatsEnvironment, secondWins: .environmentBeatsEnvFile,
                            negations: negations)
        }
        return found
    }

    /// The first verb with one source before it and the other after it decides.
    static func winner(_ text: String, first: [String], second: [String], firstWins: Statement,
                       secondWins: Statement, negations: Int = 0) -> [Statement] {
        let verbs = (winVerbs.map { ($0, true) } + loseVerbs.map { ($0, false) }).flatMap { verb, active in
            ranges(of: " " + verb + " ", in: text).map { ($0, active) }
        }.sorted { $0.0.lowerBound < $1.0.lowerBound }
        for (verb, active) in verbs {
            let before = String(text[..<verb.lowerBound])
            let after = String(text[verb.upperBound...])
            let subjectIsFirst: Bool
            if let one = last(first, in: before), last(second, in: before).map({ one > $0 }) ?? true,
               second.contains(where: after.contains) {
                subjectIsFirst = true
            } else if last(second, in: before) != nil, first.contains(where: after.contains) {
                subjectIsFirst = false
            } else {
                continue
            }
            let near = " " + before.split(separator: " ").suffix(3).joined(separator: " ") + " "
            guard negations == negationCount(near) else { return [] }
            return [(subjectIsFirst == active) != isNegated(before) ? firstWins : secondWins]
        }
        return []
    }

    static func last(_ terms: [String], in text: String) -> String.Index? {
        terms.compactMap { text.range(of: $0, options: .backwards)?.lowerBound }.max()
    }

    static func ranges(of phrase: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var start = text.startIndex
        while let range = text.range(of: phrase, range: start..<text.endIndex) {
            found.append(range)
            start = range.upperBound
        }
        return found
    }

    static func expose(_ raw: String, _ text: String, _ negations: Int) -> [Statement] {
        guard raw.contains("`expose`") || raw.contains("`expose:`") || raw.contains("`expose") else { return [] }
        let inside = ["other services", "other containers", "linked services", "same network", "internal"]
        if Words.contains(text, "only"), Words.containsAny(text, inside) {
            return [.exposeStaysInternal]
        }
        guard Words.containsAny(text, ["host", "your machine", "localhost", "browser", "outside", "laptop"]) else {
            return []
        }
        let verbs = ["publish", "publishes", "published", "reachable", "accessible", "available"]
        guard let negated = polarity(text, topics: ["expose"], verbs: verbs, negations: negations) else { return [] }
        return [negated ? .exposeStaysInternal : .exposePublishes]
    }

    /// "`5432:5432` is only reachable from your machine": about a mapping written without a host address.
    static func binding(_ raw: String, _ text: String) -> [Statement] {
        let codes = Sentences.pieces(raw).filter(\.isCode).map(\.text)
        let mappings = codes.filter { code in
            code.split(separator: ":").count >= 2 && code.split(separator: ":").allSatisfy { Int($0) != nil }
        }
        let withAddress = codes.contains { $0.split(separator: ":").count == 3 }
        guard !mappings.isEmpty || Words.containsAny(text, ["ports:", "published port", "publishing a port"]),
              !withAddress else { return [] }
        let local = ["only from localhost", "only reachable from localhost", "only on localhost",
                     "only from your machine", "only accessible from your machine", "only locally",
                     "only from the host", "only reachable from your machine", "only reachable locally",
                     "only from this machine", "localhost only", "only to localhost", "only bound to localhost"]
        if local.contains(where: text.contains) { return [.publishesOnLocalhostOnly] }
        let every = ["all interfaces", "0.0.0.0", "every interface", "from other machines", "from your network",
                     "from anywhere", "on your lan", "every network interface"]
        if every.contains(where: text.contains) {
            return [.publishesOnAllInterfaces]
        }
        return []
    }

    /// Which side of `HOST:CONTAINER` is which.
    static func order(_ text: String) -> [Statement] {
        let hostFirst = ["first number is the host", "first is the host", "left is the host", "left side is the host",
                         "host port comes first", "host:container", "host_port:container_port",
                         "the host port is first", "host port first"]
        let containerFirst = ["first number is the container", "first is the container", "left is the container",
                              "left side is the container", "container port comes first", "container:host",
                              "container_port:host_port", "the container port is first", "container port first"]
        switch (hostFirst.contains(where: text.contains), containerFirst.contains(where: text.contains)) {
        case (true, false): return [.hostPortFirst]
        case (false, true): return [.containerPortFirst]
        default: return []
        }
    }

    static func localhost(_ text: String, _ negations: Int) -> [Statement] {
        guard Words.containsAny(text, ["localhost", "127.0.0.1"]), !text.contains("network_mode"),
              !text.contains("host network") else { return [] }
        let itself = ["the container itself", "that container itself", "the container's own", "its own container",
                      "refers to the container", "means the container"]
        if itself.contains(where: text.contains) { return [.localhostIsOwnContainer] }
        guard Words.containsAny(text, ["other service", "other services", "other container", "other containers",
                                       "each other", "another service", "another container"]) else { return [] }
        let verbs = ["reach", "reaches", "connect", "connects", "talk", "talks", "access", "call"]
        let topics = ["localhost", "127.0.0.1", "container", "containers", "service", "services"]
        guard let negated = polarity(text, topics: topics, verbs: verbs, negations: negations) else { return [] }
        return [negated ? .localhostIsOwnContainer : .localhostReachesServices]
    }
}
