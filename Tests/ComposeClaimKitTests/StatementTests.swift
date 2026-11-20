import Testing
@testable import ComposeClaimKit

@Suite("Reading statements")
struct StatementTests {
    typealias Statement = ComposeClaim.Statement

    @Test(arguments: [
        ("`depends_on` makes sure the database is ready before the app starts.", Statement.dependsOnWaitsForReady),
        ("depends on waits until Postgres is accepting connections.", .dependsOnWaitsForReady),
        ("`depends_on` does not wait for the database to be ready.", .dependsOnOrdersStart),
        ("`depends_on` only waits for the container to start, not until it is ready.", .dependsOnOrdersStart),
        ("Variables in `.env` are available inside the container.", .dotEnvReachesContainer),
        ("The `.env` values are not passed to the containers.", .dotEnvForSubstitution),
        ("`.env` is only used for substitution in the compose file.", .dotEnvForSubstitution),
        ("`.env` is used for interpolation and isn't sent to containers.", .dotEnvForSubstitution),
        ("`.env` takes precedence over the shell.", .dotEnvBeatsShell),
        ("Your shell's exported variables override `.env`.", .shellBeatsDotEnv),
        ("`.env` is overridden by the shell.", .shellBeatsDotEnv),
        ("The shell is overridden by `.env`.", .dotEnvBeatsShell),
        ("`.env` does not override the shell.", .shellBeatsDotEnv),
        ("`env_file` overrides `environment` for the same key.", .envFileBeatsEnvironment),
        ("`environment` takes precedence over `env_file`.", .environmentBeatsEnvFile),
        ("A key in `env_file` is replaced by the one in `environment:`.", .environmentBeatsEnvFile),
        ("With `expose`, the port is published to the host.", .exposePublishes),
        ("`expose` does not make the port reachable from your browser.", .exposeStaysInternal),
        ("`expose` only opens it to other services on the same network.", .exposeStaysInternal),
        ("Publishing `5432:5432` is only reachable from localhost.", .publishesOnLocalhostOnly),
        ("With `ports:` the database listens on all interfaces.", .publishesOnAllInterfaces),
        ("In a mapping the first number is the host port.", .hostPortFirst),
        ("The format is container:host.", .containerPortFirst),
        ("Inside a container, `localhost` refers to the container itself.", .localhostIsOwnContainer),
        ("Containers talk to each other on `localhost`.", .localhostReachesServices),
        ("You cannot reach other services on localhost.", .localhostIsOwnContainer),
        ("Of the shell and `.env`, `.env` wins over the shell.", .dotEnvBeatsShell),
        ("The shell overrides `.env`, and `.env` overrides nothing else.", .shellBeatsDotEnv),
        ("It overrides defaults, and `.env` beats the shell.", .dotEnvBeatsShell)
    ])
    func reads(sentence: String, statement: Statement) {
        #expect(StatementReader.statements(in: sentence) == [statement], "\(sentence)")
    }

    @Test(arguments: [
        "With `condition: service_healthy`, `depends_on` waits until the database is ready.",
        "`depends_on` controls the order.",
        "`depends_on` and readiness are different things, and it would wait if you add a healthcheck.",
        "`.env` sets `TAG` for the container through `env_file`.",
        "Put `TAG` in `.env`.",
        "`.env` lives next to the compose file.",
        "`.env` and the shell both set `TAG`.",
        "`env_file` and `environment` both list the key.",
        "`expose` is a list.",
        "We expose port 80 to the host with `ports`.",
        "`expose` lists the port.",
        "`5432:5432` publishes the port.",
        "`127.0.0.1:5432:5432` is only reachable from localhost.",
        "Publishing `5432:5432` is not reachable from other machines.",
        "The first number is the host and the left side is the container.",
        "Use `localhost` from your browser.",
        "`localhost` with `network_mode: host` reaches other services.",
        "`localhost` is fast.",
        "People think `.env` takes precedence over the shell.",
        "Kubernetes `ports` work differently."
    ])
    func ignores(sentence: String) {
        #expect(StatementReader.statements(in: sentence).isEmpty, "\(sentence)")
    }

    @Test func negation() {
        #expect(StatementReader.negated(" x waits ", before: ["nope"]) == nil)
        #expect(StatementReader.negated(" it won't wait ", before: ["wait"]) == true)
        #expect(StatementReader.negated(" it shouldn't wait ", before: ["wait"]) == true)
        #expect(StatementReader.ranges(of: "a", in: "banana").count == 3)
        #expect(StatementReader.winner(" .env shell ", first: [".env"], second: ["shell"],
                                       firstWins: .dotEnvBeatsShell, secondWins: .shellBeatsDotEnv).isEmpty)
        #expect(StatementReader.winner(" x overrides y ", first: [".env"], second: ["shell"],
                                       firstWins: .dotEnvBeatsShell, secondWins: .shellBeatsDotEnv).isEmpty)
    }
}
