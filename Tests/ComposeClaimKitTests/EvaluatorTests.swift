import Testing
@testable import ComposeClaimKit

@Suite("Judging claims")
struct EvaluatorTests {
    let stackScene = sceneOf(webAndDB)

    func address(_ vantage: ComposeVantage, _ host: String, _ port: Int, variable: String? = nil)
        -> ComposeClaim.Subject {
        .address(ComposeClaim.Address(vantage: vantage, host: host, port: port, variable: variable))
    }

    @Test func fromTheHost() {
        #expect(judge(address(.host, "localhost", 8080), stackScene).outcome == .exact)
        #expect(judge(address(.host, "localhost", 80), stackScene).slip == .containerPortFromHost)
        #expect(judge(address(.host, "localhost", 9999), stackScene).severity == .unchecked)
        let ranged = sceneOf("services:\n  w:\n    image: x\n    ports:\n      - \"9090-9091:80\"\n      - \"3000\"\n"
            + "    expose: [\"4000\"]\n")
        #expect(judge(address(.host, "localhost", 9091), ranged).outcome == .caveat(.portFromRange))
        #expect(judge(address(.host, "localhost", 9091), ranged, policy: .lenient).outcome == .exact)
        let random = judge(address(.host, "localhost", 3000), ranged)
        #expect(random.slip == .containerPortFromHost && random.actual?.contains("Docker picks") == true)
        #expect(judge(address(.host, "localhost", 4000), ranged).slip == .exposePublishes)
        let bound = sceneOf("services:\n  w:\n    image: x\n    ports:\n      - \"10.0.0.2:8080:80\"\n")
        #expect(judge(address(.host, "localhost", 8080), bound).severity == .unchecked)
    }

    @Test func betweenContainers() {
        #expect(judge(address(.service("app"), "db", 5432), stackScene).outcome == .exact)
        #expect(judge(address(.service(nil), "db", 5433), stackScene).slip == .publishedPortInsideNetwork)
        #expect(judge(address(.service("app"), "db", 6000), stackScene).severity == .unchecked)
        #expect(judge(address(.service("app"), "queue", 5672), stackScene).severity == .unchecked)
        #expect(judge(address(.service("app"), "localhost", 5432), stackScene).slip == .localhostIsAnotherContainer)
        #expect(judge(address(.service("db"), "localhost", 5432), stackScene).outcome == .exact)
        #expect(judge(address(.service(nil), "localhost", 5432), stackScene).severity == .unchecked)
        #expect(judge(address(.service("app"), "localhost", 7777), stackScene).severity == .unchecked)
        let hostRead = judge(address(.service("app"), "localhost", 80, variable: "API_URL"), stackScene)
        #expect(hostRead.slip == .localhostIsAnotherContainer)
        let browser = sceneOf("services:\n  api:\n    image: x\n    ports: [\"8000:8000\"]\n  ui:\n    image: y\n")
        #expect(judge(address(.service("ui"), "localhost", 8000, variable: "API"), browser).outcome
            == .caveat(.readOnHostOnly))
    }

    @Test func blockedServices() {
        let opaque = sceneOf("services:\n  a:\n    image: x\n    extends: base\n    ports: [\"80:80\"]\n")
        #expect(judge(address(.host, "localhost", 80), opaque).outcome.unchecked?.contains("extends") == true)
        let variable = sceneOf("services:\n  a:\n    image: x\n    ports: [\"${P:-80}:80\"]\n")
        #expect(judge(address(.host, "localhost", 80), variable).outcome.unchecked?.contains("`P`") == true)
        let custom = sceneOf("services:\n  a:\n    image: x\n    network_mode: host\n  b:\n    image: y\n")
        #expect(judge(address(.service("b"), "a", 80), custom).outcome.unchecked?.contains("networking") == true)
        #expect(judge(address(.service("a"), "localhost", 6379), custom).severity == .unchecked)
        let none = Scene()
        #expect(judge(address(.host, "localhost", 80), none).outcome.unchecked?.contains("no compose file") == true)
        let broken = Scene(reading: .unreadable("why"))
        #expect(judge(.mapping(published: 1, target: 2), broken).outcome == .unchecked("why"))
    }

    @Test func mappings() {
        #expect(judge(.mapping(published: 8080, target: 80), stackScene).outcome == .exact)
        let swapped = judge(.mapping(published: 80, target: 8080), stackScene)
        #expect(swapped.slip == .hostAndContainerSwapped)
        #expect(judge(.mapping(published: 1, target: 2), stackScene).severity == .unchecked)
        #expect(judge(.mapping(published: 1, target: 2), Scene()).severity == .unchecked)
    }

    func resolves(_ expression: String, _ claimed: ResolveOutcome, _ condition: ResolveCondition? = nil)
        -> ComposeClaim.Subject {
        .resolves(ComposeClaim.Resolves(expression: expression, condition: condition, claimed: claimed))
    }

    @Test func substitutions() {
        let variables = Scene(variables: Variables(shell: ["TAG": "sh"], dotEnv: ["TAG": "file", "E": ""]))
        #expect(judge(resolves("${TAG}", .value("sh")), variables).outcome == .exact)
        #expect(judge(resolves("${TAG}", .value("file")), variables).slip == .dotEnvBeatsShell)
        #expect(judge(resolves("${E-d}", .value("d")), variables).slip == .dashCoversEmpty)
        #expect(judge(resolves("${E:-d}", .value("")), variables).slip == .colonDashKeepsEmpty)
        #expect(judge(resolves("${E?x}", .failure), variables).slip == .questionCoversEmpty)
        #expect(judge(resolves("$$TAG", .value("sh")), variables).slip == .dollarDollarExpands)
        #expect(judge(resolves("${E:?x}", .failure), variables).outcome == .exact)
        #expect(judge(resolves("${TAG}", .value("zzz")), variables).severity == .unchecked)
        #expect(judge(resolves("${NOPE}", .value("")), variables).outcome.unchecked?.contains("`NOPE`") == true)
        #expect(judge(resolves("${", .value("")), variables).outcome.unchecked?.contains("does not follow") == true)
        #expect(judge(resolves("${N:-d}", .value("d"), .unset("N")), variables).outcome == .exact)
        #expect(judge(resolves("${TAG:-d}", .value("d"), .unset("TAG")), variables).outcome == .exact)
        #expect(judge(resolves("${N-d}", .value("d"), .empty("N")), variables).slip == .dashCoversEmpty)
        #expect(judge(resolves("${N}", .value("v"), .set("N", "v")), variables).outcome == .exact)
        #expect(ComposeEvaluator.describe(.unknown([])) == ComposeEvaluator.describe(.malformed))
    }

    @Test func lines() {
        let undefined = judge(.line(.undefinedDependency("cache"), service: "app"), stackScene)
        #expect(undefined.severity == .unchecked && undefined.actual?.contains("undefined service") == true)
        let healthy = judge(.line(.healthyWithoutHealthcheck("db"), service: "app"), stackScene)
        #expect(healthy.outcome == .caveat(.imageMayHaveHealthcheck))
        #expect(judge(.line(.healthyWithoutHealthcheck("db"), service: "app"), stackScene, policy: .lenient).outcome
            == .exact)
    }

    @Test(arguments: ComposeClaim.Statement.allCases)
    func statements(statement: ComposeClaim.Statement) {
        let finding = judge(.statement(statement), Scene())
        let wrong = finding.severity == .wrong
        let wrongOnes: Set<ComposeClaim.Statement> = [.dependsOnWaitsForReady, .dotEnvReachesContainer,
                                                       .dotEnvBeatsShell, .envFileBeatsEnvironment, .exposePublishes,
                                                       .publishesOnLocalhostOnly, .containerPortFirst,
                                                       .localhostReachesServices]
        #expect(wrong == wrongOnes.contains(statement))
        #expect(finding.explanation.hasSuffix("."))
    }
}

extension ComposeFinding.Outcome {
    var unchecked: String? {
        if case let .unchecked(reason) = self { return reason }
        return nil
    }
}
