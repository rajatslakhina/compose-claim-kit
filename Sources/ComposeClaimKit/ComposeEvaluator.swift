/// Judges claims with compose's and Docker's rules, as probed against `docker compose config` and running
/// containers.
struct ComposeEvaluator {
    let policy: ComposePolicy

    func judge(_ claim: ComposeClaim) -> ComposeFinding {
        let finding = switch claim.subject {
        case let .address(address): judgeAddress(address, claim)
        case let .mapping(published, target): judgeMapping(published, target, claim)
        case let .resolves(resolves): judgeResolves(resolves, claim)
        case let .statement(statement): ComposeFinding(claim: claim, outcome: Self.outcome(of: statement))
        case let .line(line, service): judgeLine(line, service, claim)
        }
        if case .caveat = finding.outcome, !policy.reportsCaveats {
            return ComposeFinding(claim: claim, outcome: .exact, actual: finding.actual)
        }
        return finding
    }

    static func outcome(of statement: ComposeClaim.Statement) -> ComposeFinding.Outcome {
        switch statement {
        case .dependsOnOrdersStart, .dotEnvForSubstitution, .shellBeatsDotEnv, .environmentBeatsEnvFile,
             .exposeStaysInternal, .publishesOnAllInterfaces, .hostPortFirst, .localhostIsOwnContainer: .exact
        case .dependsOnWaitsForReady: .wrong(.startedMeansReady)
        case .dotEnvReachesContainer: .wrong(.dotEnvReachesContainer)
        case .dotEnvBeatsShell: .wrong(.dotEnvBeatsShell)
        case .envFileBeatsEnvironment: .wrong(.envFileBeatsEnvironment)
        case .exposePublishes: .wrong(.exposePublishes)
        case .publishesOnLocalhostOnly: .wrong(.defaultBindIsLocal)
        case .containerPortFirst: .wrong(.hostAndContainerSwapped)
        case .localhostReachesServices: .wrong(.localhostIsAnotherContainer)
        }
    }

    /// The finding for a claim with no project to judge it against.
    func missing(_ claim: ComposeClaim) -> ComposeFinding {
        if case let .unreadable(reason)? = claim.scene.reading {
            return ComposeFinding(claim: claim, outcome: .unchecked(reason))
        }
        return ComposeFinding(claim: claim, outcome: .unchecked("the conversation shows no compose file"))
    }

    func judgeAddress(_ address: ComposeClaim.Address, _ claim: ComposeClaim) -> ComposeFinding {
        guard let project = claim.scene.project else { return missing(claim) }
        if let blocked = blocked(address, project) { return ComposeFinding(claim: claim, outcome: .unchecked(blocked)) }
        switch address.vantage {
        case .host: return fromHost(address.port, project, claim)
        case let .service(from):
            if address.isLoopback { return loopback(address, from: from, project, claim) }
            return betweenServices(address, project, claim)
        }
    }

    /// Why the address cannot be judged: a service it involves is opaque, uses its own networking, or has ports
    /// that depend on an unset variable.
    func blocked(_ address: ComposeClaim.Address, _ project: ComposeProject) -> String? {
        var involved = project.services.filter { $0.containerPorts.contains(address.port)
            || $0.ports.contains { $0.published?.contains(address.port) == true } || $0.answers(to: address.host) }
        if case let .service(name?) = address.vantage, let from = project.service(name) { involved.append(from) }
        for service in involved {
            if let opaque = service.opaque { return "`\(service.name)` cannot be checked: \(opaque)" }
            if let name = service.portsAssumeUnset.min() {
                return "`\(service.name)`'s ports use `\(name)`, which the conversation does not set"
            }
            if service.hasCustomNetworking, address.vantage != .host {
                return "`\(service.name)` sets its own networking (`network_mode`, `networks`, `extra_hosts` or "
                    + "`links`)"
            }
        }
        return nil
    }

    func fromHost(_ port: Int, _ project: ComposeProject, _ claim: ComposeClaim) -> ComposeFinding {
        let published = project.services.flatMap { service in
            service.ports.filter { $0.isOnLoopback && $0.published?.contains(port) == true }.map { (service, $0) }
        }
        if let (service, mapping) = published.first(where: { $0.1.published?.count == 1 }) {
            return ComposeFinding(claim: claim, outcome: .exact,
                                  actual: "`\(service.name)` publishes `\(mapping.display)`")
        }
        if let (service, mapping) = published.first {
            return ComposeFinding(claim: claim, outcome: .caveat(.portFromRange),
                                  actual: "`\(service.name)` publishes `\(mapping.display)`")
        }
        for service in project.services {
            if let mapping = service.ports.first(where: { $0.target == port }) {
                let actual = mapping.published == nil
                    ? "`\(service.name)` publishes container port \(port) on a host port Docker picks at start"
                    : "`\(service.name)` publishes container port \(port) as `\(mapping.display)`"
                return ComposeFinding(claim: claim, outcome: .wrong(.containerPortFromHost), actual: actual)
            }
            if service.exposed.contains(port) {
                return ComposeFinding(claim: claim, outcome: .wrong(.exposePublishes),
                                      actual: "`\(service.name)` only exposes \(port) to other containers")
            }
        }
        return ComposeFinding(claim: claim, outcome: .unchecked("no service publishes or exposes port \(port)"))
    }

    func betweenServices(_ address: ComposeClaim.Address, _ project: ComposeProject,
                         _ claim: ComposeClaim) -> ComposeFinding {
        guard let target = project.service(address.host) else {
            return ComposeFinding(claim: claim, outcome: .unchecked("`\(address.host)` is not a service of the file"))
        }
        if target.containerPorts.contains(address.port) {
            return ComposeFinding(claim: claim, outcome: .exact)
        }
        if let mapping = target.ports.first(where: { $0.published?.contains(address.port) == true }) {
            return ComposeFinding(claim: claim, outcome: .wrong(.publishedPortInsideNetwork),
                                  actual: "`\(target.name):\(mapping.target)` (the container port of "
                                      + "`\(mapping.display)`)")
        }
        return ComposeFinding(claim: claim, outcome: .unchecked(
            "`\(target.name)` does not declare port \(address.port), though its program may listen on it"))
    }

    func loopback(_ address: ComposeClaim.Address, from name: String?, _ project: ComposeProject,
                  _ claim: ComposeClaim) -> ComposeFinding {
        guard let name, let from = project.service(name) else {
            return ComposeFinding(claim: claim, outcome: .unchecked("the container it is used from is not known"))
        }
        if from.containerPorts.contains(address.port) { return ComposeFinding(claim: claim, outcome: .exact) }
        guard let other = project.services.first(where: { $0 != from && $0.containerPorts.contains(address.port) })
        else {
            return ComposeFinding(claim: claim, outcome: .unchecked("no service declares port \(address.port)"))
        }
        let actual = "`\(other.name):\(address.port)`"
        let onHost = project.services.contains { service in
            service.ports.contains { $0.isOnLoopback && $0.published?.contains(address.port) == true }
        }
        if address.variable != nil, onHost {
            return ComposeFinding(claim: claim, outcome: .caveat(.readOnHostOnly), actual: actual)
        }
        return ComposeFinding(claim: claim, outcome: .wrong(.localhostIsAnotherContainer), actual: actual)
    }

    func judgeMapping(_ published: Int, _ target: Int, _ claim: ComposeClaim) -> ComposeFinding {
        guard let project = claim.scene.project else { return missing(claim) }
        let mappings = project.services.flatMap(\.ports)
        if mappings.contains(where: { $0.published == published...published && $0.target == target }) {
            return ComposeFinding(claim: claim, outcome: .exact)
        }
        if let swapped = mappings.first(where: { $0.published == target...target && $0.target == published }) {
            return ComposeFinding(claim: claim, outcome: .wrong(.hostAndContainerSwapped),
                                  actual: "`\(swapped.display)` maps host port \(target) to container port "
                                      + "\(published)")
        }
        return ComposeFinding(claim: claim, outcome: .unchecked("the compose file has no such port mapping"))
    }

    func judgeLine(_ line: ComposeClaim.Line, _ service: String, _ claim: ComposeClaim) -> ComposeFinding {
        switch line {
        case let .undefinedDependency(name):
            ComposeFinding(claim: claim, outcome: .wrong(nil),
                           actual: "service \"\(service)\" depends on undefined service \"\(name)\"")
        case let .healthyWithoutHealthcheck(name):
            ComposeFinding(claim: claim, outcome: .caveat(.imageMayHaveHealthcheck),
                           actual: "container for \"\(name)\" has no healthcheck configured")
        }
    }
}
