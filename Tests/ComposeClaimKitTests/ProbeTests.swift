import Testing
@testable import ComposeClaimKit

/// Answer shapes written from real compose questions, not from the readers: correct ones must stay quiet, wrong ones
/// must be caught with the right slip, and other domains must make no claim.
@Suite("Probes")
struct ProbeTests {
    static let project = yaml(
        "services:",
        "  api:",
        "    build: ./api",
        "    ports:",
        "      - \"8000:8000\"",
        "    environment:",
        "      DATABASE_URL: postgres://postgres:postgres@db:5432/postgres",
        "      REDIS_URL: redis://redis:6379/0",
        "    depends_on:",
        "      db:",
        "        condition: service_healthy",
        "    healthcheck:",
        "      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:8000/health\"]",
        "  web:",
        "    build: ./web",
        "    ports:",
        "      - \"3000:3000\"",
        "  db:",
        "    image: postgres:16",
        "    ports:",
        "      - \"127.0.0.1:5432:5432\"",
        "    healthcheck:",
        "      test: [\"CMD-SHELL\", \"pg_isready -U postgres\"]",
        "  redis:",
        "    image: redis:7-alpine",
        "    ports:",
        "      - \"6380:6379\"",
        "  worker:",
        "    build: ./worker",
        "    expose:",
        "      - \"9000\""
    )
    let checker = ComposeClaimChecker()

    @Test(arguments: [
        "Run `docker compose up -d` and visit http://localhost:3000.",
        "From the host, the API is at `localhost:8000`.",
        "`db` is the service name, so the `api` service connects to `db:5432` through Docker's DNS.",
        "Containers on the same network reach each other by service name, so `web` calls `api:8000`.",
        "The healthcheck curls `http://localhost:8000/health` inside the container.",
        "Because the mapping is `127.0.0.1:5432:5432`, the database is only reachable from your machine.",
        "`depends_on` with `condition: service_healthy` waits until the healthcheck passes.",
        "Compose reads `.env` automatically and substitutes `${POSTGRES_PASSWORD}` in the file.",
        "To pass `.env` values into the container, add `env_file: .env` to the service.",
        "`ports: - \"3000:3000\"` maps port 3000 on the host to port 3000 in the container.",
        "If `TAG` is not set, `${TAG:-latest}` falls back to `latest`.",
        "Use `redis:6379` from `worker`, and `localhost:6380` from your laptop.",
        "`expose` only makes `9000` available to other services on the same network.",
        "Plain `depends_on` only waits for the container to start, so add a healthcheck if you need readiness.",
        "Your shell's environment wins over `.env` when both set a variable.",
        "Inside a container, `localhost` is the container itself, so use the service name instead.",
        "The `env_file` values are overridden by `environment:` when both define a key.",
        "With `TAG` unset, `${TAG:-latest}` becomes `latest`, and with `TAG=1.2` it becomes `1.2`.",
        "In `HOST:CONTAINER` the host port is first.",
        "Open `http://localhost:8000/docs` in your browser for the API docs.",
        "Variables set in `.env` are not passed to the container.",
        "`expose` makes the port available to other containers, not to the host.",
        "`depends_on` only orders startup; use a wait script to wait for the database to be ready.",
        "To connect to another service, use its name instead of `localhost`.",
        "`.env` overrides the default in `${TAG:-latest}`; your shell overrides both.",
        "`3000:3000` listens on all interfaces, not only on localhost.",
        "The `web` service is available at `http://localhost:3000`.",
        "Vite is listening on `0.0.0.0:3000` inside the `web` container."
    ])
    func correct(answer: String) {
        let report = checker.check(Self.project + answer)
        #expect(report.flagged.isEmpty, "\(answer): \(report.corrections)")
    }

    @Test(arguments: [
        ("`api` reaches the database at `localhost:5432` because they are in the same compose project.",
         ComposeFinding.Slip.localhostIsAnotherContainer),
        ("Connect from the `worker` service to `redis:6380`.", .publishedPortInsideNetwork),
        ("`depends_on: [db]` guarantees Postgres is ready before `api` starts.", .startedMeansReady),
        ("Docker Compose passes every variable in `.env` to the containers.", .dotEnvReachesContainer),
        ("`expose` lets you open `http://localhost:9000` in the browser.", .exposePublishes),
        ("Compose binds `3000:3000` to localhost only, so it is safe on a shared network.", .defaultBindIsLocal),
        ("The `3000:3000` line maps container port 3000 to host port 3001.", nil),
        ("From your laptop, open `localhost:6379` to reach Redis.", .containerPortFromHost),
        ("Values in `env_file` take precedence over `environment:`.", .envFileBeatsEnvironment),
        ("With `TAG` empty, `${TAG-latest}` gives `latest`.", .dashCoversEmpty),
        ("`$$HOME` gives your home directory.", nil),
        ("Containers can reach each other on `localhost` in compose.", .localhostIsAnotherContainer)
    ])
    func wrong(answer: String, slip: ComposeFinding.Slip?) {
        let report = checker.check(Self.project + answer)
        if let slip {
            #expect(report.flagged.map(\.slip) == [slip], "\(answer): \(report.corrections)")
        } else {
            // A mistake the readers cannot pin down stays unflagged rather than being called wrong.
            #expect(report.flagged.isEmpty, "\(answer): \(report.corrections)")
        }
    }

    @Test(arguments: [
        "In bash, `${NAME:-guest}` gives `guest` when `NAME` is unset.",
        "In Kubernetes, a sidecar reaches the app on `localhost:8000`.",
        "Jetpack Compose's `remember` keeps state across recompositions.",
        "The regex `[a-z]+:[0-9]+` matches `localhost:8080`.",
        "nginx's `proxy_pass http://localhost:3000;` forwards requests.",
        "In GitHub Actions, the job reaches the service container at `localhost:5432`.",
        "Set `PORT=3000` and Express listens on `localhost:3000`."
    ])
    func otherDomains(answer: String) {
        #expect(checker.check(answer).verdict == .noClaims, "\(answer)")
    }

    @Test(arguments: [
        "In Kubernetes, a sidecar reaches the app on `localhost:8000`.",
        "A Kubernetes pod's containers share `localhost`, so they can reach each other there."
    ])
    func otherToolsInAComposeConversation(answer: String) {
        let report = checker.check(Self.project + answer, context: "How does this compare with my docker compose file?")
        #expect(report.flagged.isEmpty, "\(answer): \(report.corrections)")
    }

    @Test func environmentURLs() {
        let answer = yaml("services:", "  web:", "    build: .", "    ports: [\"8000:80\"]", "  api:", "    build: ./api",
                          "    ports: [\"9000:8000\"]", "    environment:", "      CORS_ORIGIN: http://localhost:8000",
                          "      DATABASE_URL: postgres://localhost:5432/app", "  db:", "    image: postgres:16",
                          "    ports: [\"5432:5432\"]")
        let report = checker.check(answer + "The `web` service is available at `http://localhost:8000`.")
        #expect(report.flagged.map(\.slip) == [.localhostIsAnotherContainer], "\(report.corrections)")
        #expect(report.flagged.first?.claim.sentence.contains("DATABASE_URL") == true)
    }

    @Test func oneCommandPrefix() {
        let answer = yaml("services:", "  web:", "    image: \"nginx:${TAG}\"") + "In `.env`:\n\n"
            + block("env", "TAG=1.27") + "`${TAG}` becomes `1.27`.\n\n" + block("bash", "TAG=1.26 docker compose up")
        #expect(checker.check(answer).verdict == .verified)
    }

    @Test func gitLabAndSymfony() {
        let gitlab = yaml("stages: [test]", "services:", "  - postgres:16", "test:", "  script: [\"pytest\"]")
        let symfony = yaml("services:", "  _defaults:", "    autowire: true", "  App\\:", "    resource: '../src/'")
        #expect(checker.check(gitlab + "The job connects to `postgres:5432`.").verdict == .noClaims)
        #expect(checker.check(symfony + "Services are autowired.").verdict == .noClaims)
    }

    @Test func laterTurnOfAnotherDomain() async {
        let ledger = ComposeLedger()
        _ = await ledger.review(Self.project + "Open `localhost:3000` in your browser.")
        let later = await ledger.review("Express listens on `localhost:4000`, so open it in your browser.",
                                        context: "How do I run the Express server without Docker?")
        #expect(later.verdict == .noClaims)
    }
}
