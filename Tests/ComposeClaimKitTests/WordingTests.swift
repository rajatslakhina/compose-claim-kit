import Testing
@testable import ComposeClaimKit

@Suite("Explanations")
struct WordingTests {
    let stackScene = sceneOf(webAndDB)

    func explain(_ subject: ComposeClaim.Subject, _ scene: Scene? = nil) -> String {
        judge(subject, scene ?? stackScene).explanation
    }

    func address(_ vantage: ComposeVantage, _ host: String, _ port: Int, variable: String? = nil)
        -> ComposeClaim.Subject {
        .address(ComposeClaim.Address(vantage: vantage, host: host, port: port, variable: variable))
    }

    @Test func addresses() {
        #expect(explain(address(.host, "localhost", 8080))
            == "`localhost:8080` works from the host (`web` publishes `8080:80`), as the answer says.")
        #expect(explain(address(.service("app"), "db", 5432)) == "`db:5432` works from inside `app`, as the answer says.")
        #expect(explain(address(.host, "localhost", 80)).contains("only through its published port"))
        #expect(explain(address(.service(nil), "db", 5433))
            == "`db:5433` does not work from another container: containers reach each other on the container port, "
            + "so use `db:5432` (the container port of `5433:5432`).")
        #expect(explain(address(.service("app"), "localhost", 5432, variable: "DB"))
            == "`DB` in `app` (`localhost:5432`) does not work from inside `app`: inside a container `localhost` is "
            + "that container itself, so use `db:5432`.")
        #expect(explain(address(.host, "localhost", 1)) == "`localhost:1` was not checked: no service publishes or "
            + "exposes port 1.")
        let ranged = sceneOf("services:\n  w:\n    image: x\n    ports: [\"9090-9091:80\"]\n    expose: [\"4000\"]\n")
        #expect(explain(address(.host, "localhost", 9090), ranged) == "`localhost:9090` may work from the host: `w` "
            + "publishes `9090-9091:80`, and Docker picks one of those host ports at start.")
        #expect(explain(address(.host, "localhost", 4000), ranged).contains("add it under `ports:`"))
        let browser = sceneOf("services:\n  api:\n    image: x\n    ports: [\"8000:8000\"]\n  ui:\n    image: y\n")
        #expect(explain(address(.service("ui"), "localhost", 8000, variable: "API"), browser)
            == "`API` in `ui` (`localhost:8000`): that works only where the value is read on the host (a browser); "
            + "from inside `ui` the service is `api:8000`.")
        let finding = judge(address(.service("app"), "db", 5432, variable: "X"), stackScene)
        #expect(finding.explanation.hasPrefix("`X` in `app` (`db:5432`) works"))
    }

    @Test func mappingsAndSubstitutions() {
        #expect(explain(.mapping(published: 8080, target: 80))
            == "Host port 8080 maps to container port 80, as the answer says.")
        #expect(explain(.mapping(published: 80, target: 8080)) == "The mapping is the other way round: `8080:80` maps "
            + "host port 8080 to container port 80 (compose writes `HOST:CONTAINER`).")
        #expect(explain(.mapping(published: 1, target: 2))
            == "Host port 1 to container port 2 was not checked: the compose file has no such port mapping.")
        let variables = Scene(variables: Variables(shell: ["T": "sh", "E": ""], dotEnv: ["T": "file"]))
        func resolves(_ text: String, _ claimed: ResolveOutcome, _ condition: ResolveCondition? = nil) -> String {
            explain(.resolves(.init(expression: text, condition: condition, claimed: claimed)), variables)
        }
        #expect(resolves("${N:-d}", .value("d"), .unset("N")) == "`${N:-d}` gives `d` when `N` is unset, as the "
            + "answer says.")
        #expect(resolves("${E-d}", .value("d")) == "`${E-d}` does not give `d`: it gives an empty string (without a "
            + "colon, `-` uses the default only when the variable is unset, not empty).")
        #expect(resolves("${N:-d}", .value(""), .empty("N")).contains("unset or empty"))
        #expect(resolves("${N?x}", .failure, .empty("N")).contains("does not give an error that stops"))
        #expect(resolves("${N?x}", .failure, .empty("N")).contains("fails only when the variable is unset"))
        #expect(resolves("$$T", .value("sh")).contains("`$$` is a literal `$`"))
        #expect(resolves("${T}", .value("file"), .set("U", "1")).contains("when `U` is `1`: it gives `sh` (the shell"))
        #expect(resolves("${Z}", .value("")) == "`${Z}` was not checked: it depends on `Z`, which the conversation "
            + "does not set.")
    }

    @Test func lines() {
        #expect(explain(.line(.undefinedDependency("cache"), service: "app")) == "`app` depends on `cache`, which "
            + "was not checked: the file shown does not define it; if the whole file does not either, compose "
            + "refuses it: service \"app\" depends on undefined service \"cache\".")
        #expect(explain(.line(.healthyWithoutHealthcheck("db"), service: "app")).hasSuffix(
            "stops with: dependency failed to start: container <project>-db-1 has no healthcheck configured."))
    }

    @Test(arguments: ComposeClaim.Statement.allCases)
    func statements(statement: ComposeClaim.Statement) {
        let text = explain(.statement(statement))
        let holds = ComposeEvaluator.outcome(of: statement) == .exact
        #expect(text.hasPrefix("The statement about ") == holds)
        #expect(!ComposeFinding.topic(statement).isEmpty)
    }
}
