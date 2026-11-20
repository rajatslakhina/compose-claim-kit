extension ComposeFinding {
    /// One sentence a reader can act on.
    public var explanation: String {
        switch claim.subject {
        case let .address(address): addressExplanation(address)
        case let .mapping(published, target): mappingExplanation(published, target)
        case let .resolves(resolves): resolvesExplanation(resolves)
        case let .statement(statement): Self.statementExplanation(statement, outcome)
        case let .line(line, service): lineExplanation(line, service)
        }
    }

    func addressExplanation(_ address: ComposeClaim.Address) -> String {
        let said = "`\(address.host):\(address.port)`"
        let place = if let variable = address.variable, case let .service(name?) = address.vantage {
            "`\(variable)` in `\(name)` (\(said))"
        } else {
            said
        }
        let actual = detail
        switch outcome {
        case .exact:
            let detail = actual.isEmpty ? "" : " (\(actual))"
            return "\(place) works \(Self.vantage(address))\(detail), as the answer says."
        case .caveat(.portFromRange):
            return "\(place) may work \(Self.vantage(address)): \(actual), and Docker picks one of those host ports "
                + "at start."
        case .caveat:
            return "\(place): that works only where the value is read on the host (a browser); "
                + "\(Self.vantage(address)) the service is \(actual)."
        case let .unchecked(reason):
            return "\(place) was not checked: \(reason)."
        case let .wrong(slip):
            return "\(place) does not work \(Self.vantage(address)): \(Self.addressReason(slip, address, actual))."
        }
    }

    static func vantage(_ address: ComposeClaim.Address) -> String {
        switch address.vantage {
        case .host: "from the host"
        case let .service(name?): "from inside `\(name)`"
        case .service(nil): "from another container"
        }
    }

    static func addressReason(_ slip: Slip?, _ address: ComposeClaim.Address, _ actual: String) -> String {
        switch slip {
        case .containerPortFromHost?:
            "\(actual), and the host reaches a container only through its published port"
        case .exposePublishes?:
            "\(actual); `expose` does not publish, so add it under `ports:`"
        case .publishedPortInsideNetwork?:
            "containers reach each other on the container port, so use \(actual)"
        default:
            "inside a container `localhost` is that container itself, so use \(actual)"
        }
    }

    func mappingExplanation(_ published: Int, _ target: Int) -> String {
        switch outcome {
        case .exact, .caveat:
            "Host port \(published) maps to container port \(target), as the answer says."
        case let .unchecked(reason):
            "Host port \(published) to container port \(target) was not checked: \(reason)."
        case .wrong:
            "The mapping is the other way round: \(detail) (compose writes `HOST:CONTAINER`)."
        }
    }

    func resolvesExplanation(_ resolves: ComposeClaim.Resolves) -> String {
        let condition = switch resolves.condition {
        case let .unset(name)?: " when `\(name)` is unset"
        case let .empty(name)?: " when `\(name)` is empty"
        case let .set(name, value)?: " when `\(name)` is `\(value)`"
        case nil: ""
        }
        let claimed = switch resolves.claimed {
        case let .value(value): ComposeEvaluator.describe(.value(value))
        case .failure: ComposeEvaluator.describe(.failure)
        }
        let expression = "`\(resolves.expression)`"
        switch outcome {
        case .exact, .caveat:
            return "\(expression) gives \(claimed)\(condition), as the answer says."
        case let .unchecked(reason):
            return "\(expression) was not checked: \(reason)."
        case let .wrong(slip):
            return "\(expression) does not give \(claimed)\(condition): it gives \(detail)"
                + " (\(Self.resolveReason(slip)))."
        }
    }

    static func resolveReason(_ slip: Slip?) -> String {
        switch slip {
        case .dashCoversEmpty?: "without a colon, `-` uses the default only when the variable is unset, not empty"
        case .colonDashKeepsEmpty?: "`:-` uses the default when the variable is unset or empty"
        case .questionCoversEmpty?: "without a colon, `?` fails only when the variable is unset, not empty"
        case .dollarDollarExpands?: "`$$` is a literal `$`, so nothing is substituted"
        default: "the shell's environment wins over `.env`"
        }
    }

    func lineExplanation(_ line: ComposeClaim.Line, _ service: String) -> String {
        switch line {
        case let .undefinedDependency(name):
            "`\(service)` depends on `\(name)`, which was not checked: \(detail)."

        case let .healthyWithoutHealthcheck(name):
            "`\(service)` waits for `\(name)` to be healthy, but `\(name)` has no `healthcheck:`; unless its image "
                + "defines a HEALTHCHECK, `docker compose up` stops with: \(detail)."

        }
    }

    static func statementExplanation(_ statement: ComposeClaim.Statement, _ outcome: Outcome) -> String {
        switch statement {
        case .dependsOnOrdersStart, .dotEnvForSubstitution, .shellBeatsDotEnv, .environmentBeatsEnvFile,
             .exposeStaysInternal, .publishesOnAllInterfaces, .hostPortFirst, .localhostIsOwnContainer:
            "The statement about \(topic(statement)) holds."
        case .dependsOnWaitsForReady:
            "`depends_on` waits only for the dependency's container to start, not for it to be ready; use "
                + "`condition: service_healthy` with a `healthcheck:` for that."
        case .dotEnvReachesContainer:
            "Variables in `.env` are not set inside the containers: compose uses them for substitution in the "
                + "compose file; pass them with `env_file:` or `environment:`."
        case .dotEnvBeatsShell:
            "`.env` does not win over the shell: a variable exported in the shell takes precedence over `.env`."
        case .envFileBeatsEnvironment:
            "`env_file:` does not win over `environment:`: a variable set in both takes the `environment:` value."
        case .exposePublishes:
            "`expose` does not make a port reachable from the host: it opens it to other containers; publish it "
                + "under `ports:`."
        case .publishesOnLocalhostOnly:
            "A published port with no host address listens on every interface, not only localhost; write "
                + "`127.0.0.1:HOST:CONTAINER` to keep it local."
        case .containerPortFirst:
            "The host port comes first: compose writes `HOST:CONTAINER`, so `8080:80` maps host port 8080 to "
                + "container port 80."
        case .localhostReachesServices:
            "Containers do not reach each other on `localhost`: inside a container it is that container; use the "
                + "service name, such as `db:5432`."
        }
    }

    static func topic(_ statement: ComposeClaim.Statement) -> String {
        switch statement {
        case .dependsOnOrdersStart, .dependsOnWaitsForReady: "`depends_on` and readiness"
        case .dotEnvForSubstitution, .dotEnvReachesContainer: "what `.env` is for"
        case .shellBeatsDotEnv, .dotEnvBeatsShell: "the shell's environment and `.env`"
        case .environmentBeatsEnvFile, .envFileBeatsEnvironment: "`environment:` and `env_file:`"
        case .exposeStaysInternal, .exposePublishes: "`expose`"
        case .publishesOnAllInterfaces, .publishesOnLocalhostOnly: "where a published port listens"
        case .hostPortFirst, .containerPortFirst: "the order of `HOST:CONTAINER`"
        case .localhostIsOwnContainer, .localhostReachesServices: "`localhost` inside a container"
        }
    }
}
