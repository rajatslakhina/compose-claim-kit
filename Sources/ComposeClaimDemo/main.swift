import ComposeClaimKit

let checker = ComposeClaimChecker()
let stack = compose(
    "services:",
    "  web:",
    "    image: nginx:1.27",
    "    ports:",
    "      - \"8080:80\"",
    "  app:",
    "    build: .",
    "    environment:",
    "      DATABASE_URL: postgres://app:secret@db:5432/app",
    "    depends_on:",
    "      - db",
    "  db:",
    "    image: postgres:16",
    "    ports:",
    "      - \"5433:5432\""
)

print("ComposeClaimKit demo: what an answer says about a compose project, checked with compose's own rules")

heading(1, "A correct answer about ports, service names and depends_on")
show(checker.check(stack + "Run `docker compose up -d`, then open `http://localhost:8080` in your browser. "
    + "The `app` service connects to Postgres at `db:5432`, the container port. From your laptop, use "
    + "`localhost:5433`. `depends_on` only controls start order; it does not wait for Postgres to be ready."))

heading(2, "Host and container sides of a port mapping")
show(checker.check(stack + "The `8080:80` line maps container port 8080 to host port 80, so open "
    + "`http://localhost:80` in your browser."))

heading(3, "The published port used between containers (one mistake, one finding)")
let published = stack.replacingOccurrences(of: "@db:5432/app", with: "@db:5433/app")
show(checker.check(published + "Inside the network, the `app` service reaches Postgres at `db:5433`."))
show(checker.check(published), label: "compose file alone")

heading(4, "localhost inside a container (a URL a browser reads stays quiet)")
let frontend = compose(
    "services:",
    "  api:",
    "    build: ./api",
    "    ports:",
    "      - \"8000:8000\"",
    "    environment:",
    "      - DATABASE_URL=postgres://localhost:5432/app",
    "  frontend:",
    "    build: ./web",
    "    environment:",
    "      - VITE_API_URL=http://localhost:8000",
    "  db:",
    "    image: postgres:16"
)
show(checker.check(frontend + "This is a working `docker compose` setup for the API and its database."))

heading(5, "depends_on and readiness")
let waiting = "`depends_on` makes sure the database is ready before the app starts."
show(checker.check(stack + waiting))
let healthy = compose(
    "services:",
    "  app:",
    "    build: .",
    "    depends_on:",
    "      db:",
    "        condition: service_healthy",
    "  db:",
    "    image: postgres:16"
)
show(checker.check(healthy + "With `condition: service_healthy`, compose starts `app` once the database is healthy."),
     label: "rewrite")

heading(6, "Variable substitution and .env")
let tagged = compose("services:", "  web:", "    image: \"nginx:${TAG:-latest}\"", "    ports:",
                     "      - \"${PORT:-8080}:80\"")
let dotEnv = "Put this in `.env` next to `compose.yaml`:\n\n" + block("env", "TAG=1.27", "PORT=")
let question = "How do I pick the nginx tag and port in docker compose?"
show(checker.check(tagged + dotEnv + "Here `nginx:${TAG:-latest}` becomes `nginx:1.27`. Because `PORT` is empty, "
    + "`${PORT:-8080}` gives `8080`. With `TAG` empty, `${TAG-latest}` gives `latest`.", context: question))
show(checker.check(tagged + dotEnv + "The variables in `.env` are also available inside the container, so the app "
    + "can read `TAG`.", context: question), label: "follow-up")

heading(7, "Which value wins")
let shell = block("bash", "export TAG=1.26", "docker compose up -d")
show(checker.check(tagged + dotEnv + shell + "`.env` takes precedence over the shell, so `${TAG}` is `1.27`. "
    + "In the service, `env_file` overrides `environment` for the same key."))
show(checker.check(tagged + dotEnv + shell + "The shell's environment overrides `.env`, so `${TAG}` is `1.26`, and "
    + "`environment` takes precedence over `env_file`."), label: "rewrite")

heading(8, "expose does not publish")
let exposed = compose("services:", "  api:", "    build: .", "    expose:", "      - \"3000\"")
show(checker.check(exposed + "With `expose`, the port is published to the host, so open `http://localhost:3000` "
    + "in your browser."))
show(checker.check(exposed + "`expose` only opens the port to other services on the same network; add "
    + "`ports: [\"3000:3000\"]` to reach it from your browser."), label: "rewrite")

heading(9, "Other tools' YAML and other domains make no claims")
let actions = block("yaml", "on: push", "jobs:", "  test:", "    runs-on: ubuntu-latest", "    services:",
                    "      postgres:", "        image: postgres:16", "        ports:", "          - 5432:5432")
show(checker.check(actions + "The job connects to the database at `localhost:5432`."), label: "GitHub Actions")
show(checker.check("In bash, `${NAME:-guest}` gives `guest` when `NAME` is unset."), label: "bash")
show(checker.check("In Jetpack Compose, `remember` keeps state across recompositions."), label: "Jetpack Compose")

heading(10, "A conversation: the same mistake stated again")
let ledger = ComposeLedger()
_ = await ledger.review(stack + "Containers talk to each other on `localhost`, so `app` connects to `localhost:5432`.")
show(await ledger.review("Right, keep `localhost:5432` for the `app` service; it connects there.",
                         context: "Are you sure about docker compose networking?"), label: "turn 2")
let statistics = await ledger.statistics
print("    ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, \(statistics.flagged) flagged, "
    + "\(statistics.repeated) repeated")
