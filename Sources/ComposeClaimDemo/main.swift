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
