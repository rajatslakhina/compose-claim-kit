/// Words that decide whether, and from where, a sentence makes a claim.
enum Cues {
    /// A sentence with one of these is negated, hedged or contrasted, so its addresses and mappings are not read
    /// as claims ("don't use `localhost:5432`; use `db:5432`").
    static let blockers = ["not", "n't", "never", "no longer", "cannot", "instead of", "rather than", "avoid",
                           "unless", "would", "could", "might", "wrong", "mistake", "fails", "won't", "isn't",
                           "kubernetes", "k8s", "pod", "sidecar", "github actions", "runner"]
    /// The address is used from inside a container. Bare nouns ("the `web` service") say nothing about where.
    static let container = ["inside", "from within", "connects", "connect to", "talks to", "talk to", "calls",
                            "reaches", "from the container", "from another container", "in the container",
                            "from inside"]
    /// The address is used from the machine running Docker.
    static let host = ["browser", "open", "visit", "curl", "on your machine", "from your machine", "from your host",
                       "on the host", "from the host", "your laptop", "go to", "navigate", "reachable at",
                       "available at", "accessible at", "served at", "listening on", "hit"]

    static func blocked(_ prose: String) -> Bool {
        let text = prose.folded
        return Words.containsAny(text, blockers) || text.contains("n't")
    }

    /// The sentence's prose, without its inline code, folded for matching.
    static func prose(_ sentence: String) -> String {
        Sentences.pieces(sentence).filter { !$0.isCode }.map(\.text).joined(separator: " ").folded
    }
}
