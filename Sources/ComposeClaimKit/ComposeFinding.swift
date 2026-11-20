/// What a claim about a compose project turned out to be once compose's and Docker's rules were applied.
public struct ComposeFinding: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case exact
        /// Holds, with something a reader should know.
        case caveat(Caveat)
        case wrong(Slip?)
        /// Could not be checked, and why.
        case unchecked(String)
    }

    public enum Caveat: String, Sendable, Hashable, CaseIterable {
        /// The host port comes from a range: Docker picks one of them at start.
        case portFromRange
        /// The image may define a `HEALTHCHECK`, which the conversation does not show.
        case imageMayHaveHealthcheck
        /// `localhost` in a service's environment works only if the value is read on the host (by a browser).
        case readOnHostOnly
    }

    /// A recognisable mistake behind a wrong claim.
    public enum Slip: String, Sendable, Hashable, CaseIterable {
        /// The host and container sides of `HOST:CONTAINER` read the other way round.
        case hostAndContainerSwapped
        /// The container port used from the host: only the published (host) port is reachable there.
        case containerPortFromHost
        /// `expose:` read as publishing to the host.
        case exposePublishes
        /// The published (host) port used between containers: they reach each other on the container port.
        case publishedPortInsideNetwork
        /// `localhost` used to reach another service: inside a container it is that container.
        case localhostIsAnotherContainer
        /// A published port read as bound to the host's loopback: with no address it listens on every interface.
        case defaultBindIsLocal
        /// `depends_on` read as waiting for readiness: it waits for the container to start.
        case startedMeansReady
        /// `.env` read as setting variables inside the containers.
        case dotEnvReachesContainer
        /// `.env` read as winning over the shell's environment.
        case dotEnvBeatsShell
        /// `env_file:` read as winning over `environment:`.
        case envFileBeatsEnvironment
        /// `${VAR-default}` read as using the default when `VAR` is empty: only when it is unset.
        case dashCoversEmpty
        /// `${VAR:-default}` read as keeping an empty value: the colon form uses the default for empty too.
        case colonDashKeepsEmpty
        /// `${VAR?message}` read as failing when `VAR` is empty: only when it is unset.
        case questionCoversEmpty
        /// `$$VAR` read as the variable's value: `$$` is a literal `$`.
        case dollarDollarExpands
    }

    public enum Severity: Int, Sendable, Hashable, Comparable {
        case holds
        case unchecked
        case caution
        case wrong

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let claim: ComposeClaim
    public let outcome: Outcome
    /// What compose or Docker actually does, in words, where the claim gets it wrong or needs a note.
    public var actual: String? {
        detail.isEmpty ? nil : detail
    }

    /// `actual`, or empty.
    let detail: String
    /// Flagged in an earlier review of the same conversation (set by `ComposeLedger`).
    public internal(set) var isRepeated = false

    init(claim: ComposeClaim, outcome: Outcome, actual: String = "") {
        self.claim = claim
        self.outcome = outcome
        detail = actual
    }

    public var severity: Severity {
        switch outcome {
        case .exact: .holds
        case .unchecked: .unchecked
        case .caveat: .caution
        case .wrong: .wrong
        }
    }

    var key: String {
        claim.key
    }

    /// The mistake behind a wrong finding, if it is a recognisable one.
    public var slip: Slip? {
        if case let .wrong(slip) = outcome { return slip }
        return nil
    }
}

/// How strictly claims are judged.
public struct ComposePolicy: Sendable, Hashable {
    /// Also report what the answer's compose file does that it may not mean (addresses in `environment:`,
    /// `depends_on` problems).
    public var checksLines: Bool
    /// Report claims that hold with a caveat as cautions; when `false` they count as holding.
    public var reportsCaveats: Bool

    public init(checksLines: Bool = true, reportsCaveats: Bool = true) {
        self.checksLines = checksLines
        self.reportsCaveats = reportsCaveats
    }

    public static let standard = ComposePolicy()
    public static let lenient = ComposePolicy(checksLines: false, reportsCaveats: false)
}
