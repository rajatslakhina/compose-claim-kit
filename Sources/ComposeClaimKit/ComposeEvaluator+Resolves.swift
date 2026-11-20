extension ComposeEvaluator {
    enum Evaluation: Hashable {
        case value(String)
        case failure
        case unknown(Set<String>)
        case malformed
    }

    static let misreadings: [(ComposeFinding.Slip, Interpolation.Semantics)] = [
        (.dashCoversEmpty, Interpolation.Semantics(dashCoversEmpty: true)),
        (.colonDashKeepsEmpty, Interpolation.Semantics(colonDashKeepsEmpty: true)),
        (.questionCoversEmpty, Interpolation.Semantics(questionCoversEmpty: true)),
        (.dollarDollarExpands, Interpolation.Semantics(dollarDollarExpands: true)),
        (.dotEnvBeatsShell, Interpolation.Semantics(dotEnvFirst: true))
    ]

    static func evaluate(_ expression: String, _ variables: Variables,
                         _ semantics: Interpolation.Semantics = Interpolation.Semantics()) -> Evaluation {
        do {
            let result = try Interpolation.resolve(expression, variables, semantics)
            return result.unknown.isEmpty ? .value(result.value) : .unknown(result.unknown)
        } catch .required {
            return .failure
        } catch {
            return .malformed
        }
    }

    static func variables(_ scene: Variables, _ condition: ResolveCondition?) -> Variables {
        var variables = scene
        switch condition {
        case let .unset(name)?:
            variables.unset.insert(name)
        case let .empty(name)?:
            variables.unset.remove(name)
            variables.shell[name] = ""
        case let .set(name, value)?:
            variables.unset.remove(name)
            variables.shell[name] = value
        case nil:
            break
        }
        return variables
    }

    func judgeResolves(_ resolves: ComposeClaim.Resolves, _ claim: ComposeClaim) -> ComposeFinding {
        let variables = Self.variables(claim.scene.variables, resolves.condition)
        let claimed: Evaluation = switch resolves.claimed {
        case let .value(value): .value(value)
        case .failure: .failure
        }
        let actual = Self.evaluate(resolves.expression, variables)
        switch actual {
        case let .unknown(names):
            let list = names.sorted().map { "`\($0)`" }.joined(separator: ", ")
            return ComposeFinding(claim: claim, outcome: .unchecked("it depends on \(list), which the conversation "
                + "does not set"))
        case .malformed:
            return ComposeFinding(claim: claim, outcome: .unchecked("it uses substitution this reader does not follow"))
        case .value, .failure:
            break
        }
        let description = Self.describe(actual)
        if actual == claimed { return ComposeFinding(claim: claim, outcome: .exact, actual: description) }
        let explained = Self.misreadings.first { Self.evaluate(resolves.expression, variables, $0.1) == claimed }
        if let (slip, _) = explained {
            return ComposeFinding(claim: claim, outcome: .wrong(slip), actual: description)
        }
        return ComposeFinding(claim: claim, outcome: .unchecked("compose gives \(description), and no known mistake "
            + "explains the answer's value"))
    }

    static func describe(_ evaluation: Evaluation) -> String {
        switch evaluation {
        case let .value(value): value.isEmpty ? "an empty string" : "`\(value)`"
        case .failure, .unknown, .malformed: "an error that stops `docker compose`"
        }
    }
}
