/// Reads what an answer says about a compose project and checks every claim with compose's and Docker's rules: the
/// one call most callers need.
public struct ComposeClaimChecker: Sendable {
    public let policy: ComposePolicy
    public let reader: ComposeClaimReader

    public init(policy: ComposePolicy = .standard) {
        self.policy = policy
        reader = ComposeClaimReader(checksLines: policy.checksLines)
    }

    public func claims(in text: String, context: String = "") -> [ComposeClaim] {
        reader.claims(in: text, context: context)
    }

    public func judge(_ claim: ComposeClaim) -> ComposeFinding {
        ComposeEvaluator(policy: policy).judge(claim)
    }

    /// Every claim's finding. Something the compose file shows that works as written makes no finding of its own.
    public func check(_ text: String, context: String = "") -> ComposeReport {
        report(claims(in: text, context: context))
    }

    /// One mistake, one finding: a line whose slip a stated claim already shows is left out, and so is a second
    /// finding with the same slip from the same sentence.
    func report(_ claims: [ComposeClaim]) -> ComposeReport {
        let findings = claims.map(judge).filter { $0.claim.isExplicit || $0.severity != .holds }
        let stated = Set(findings.filter(\.claim.isExplicit).compactMap(\.slip))
        var seen: Set<String> = []
        return ComposeReport(findings: findings.filter { finding in
            guard let slip = finding.slip else { return true }
            guard finding.claim.isExplicit else { return !stated.contains(slip) }
            return seen.insert(finding.claim.sentence + "|" + slip.rawValue).inserted
        })
    }
}

/// Checks a conversation's answers one after another and remembers the last compose file, the variables shown and
/// what it flagged, so a later answer is read against them and a wrong claim stated again after a correction was
/// asked for is marked as repeated rather than new.
public actor ComposeLedger {
    public struct Statistics: Sendable, Hashable {
        public var reviews = 0
        public var claims = 0
        public var flagged = 0
        public var repeated = 0
    }

    public nonisolated let checker: ComposeClaimChecker
    public private(set) var statistics = Statistics()
    private var flaggedKeys: Set<String> = []
    private var scene = Scene()

    public init(checker: ComposeClaimChecker = ComposeClaimChecker()) {
        self.checker = checker
    }

    /// Checks one answer. `context` is the question it answers. A turn where neither talks about compose makes no
    /// new claims; it keeps only those that repeat a claim flagged earlier in the conversation.
    public func review(_ text: String, context: String = "") -> ComposeReport {
        let about = ComposeClaimReader.isAboutCompose(text) || ComposeClaimReader.isAboutCompose(context)
        let all = checker.reader.allClaims(in: text, earlier: scene)
        ComposeClaimReader.remember(text, into: &scene)
        var findings = checker.report(about ? all : all.filter { flaggedKeys.contains($0.key) }).findings
        var keys: Set<String> = []
        for index in findings.indices where findings[index].severity >= .caution {
            findings[index].isRepeated = flaggedKeys.contains(findings[index].key)
            keys.insert(findings[index].key)
        }
        flaggedKeys.formUnion(keys)
        let report = ComposeReport(findings: findings)
        statistics.reviews += 1
        statistics.claims += findings.count
        statistics.flagged += report.flagged.count
        statistics.repeated += report.repeatedCount
        return report
    }

    /// Starts a new conversation: nothing flagged so far counts as a repeat, and no compose file is remembered.
    public func forget() {
        flaggedKeys.removeAll()
        scene = Scene()
    }
}
