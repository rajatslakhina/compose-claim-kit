import Testing
@testable import ComposeClaimKit

@Suite("Answers, reports and conversations")
struct ConversationTests {
    let checker = ComposeClaimChecker()

    @Test func aboutCompose() {
        #expect(ComposeClaimReader.isAboutCompose("Run docker compose up."))
        #expect(ComposeClaimReader.isAboutCompose(stack))
        #expect(!ComposeClaimReader.isAboutCompose("In Jetpack Compose, state is remembered."))
        #expect(!ComposeClaimReader.isAboutCompose(block("bash", "echo hi")))
        #expect(checker.claims(in: "Open `localhost:8080`.").isEmpty)
        // No compose file is shown, so an address has nothing to be judged against and makes no claim.
        #expect(checker.claims(in: "Open `localhost:8080` in a browser.", context: "my docker compose file").isEmpty)
    }

    @Test func dotEnvAndShell() {
        let answer = stack + "Your `.env`:\n\n" + block("", "TAG=1.2", "# c", "PORT=") + block("ini title=\".env\"", "A=1")
            + block("bash", "$ export SHELLVAR=\"x\" OTHER=y", "TAG=9 docker compose up", "FOO=1 docker-compose up",
                    "BAR=2 make", "export bad-name=1", "echo hi") + block("sh", "export OTHER=z")
        let scene = ComposeClaimReader.scene(AnswerBlocks.split(answer), text: answer, earlier: Scene())
        #expect(scene.variables.dotEnv == ["A": "1"])
        // `TAG=9 docker compose up` sets TAG for that command only.
        #expect(scene.variables.shell == ["SHELLVAR": "x", "OTHER": "z"])
        #expect(ComposeClaimReader.isDotEnv(tag: "dotenv", info: "dotenv", lines: [], previousProse: ""))
        #expect(!ComposeClaimReader.isDotEnv(tag: "", info: "", lines: ["A=1"], previousProse: "no file"))
        #expect(!ComposeClaimReader.isDotEnv(tag: "", info: "", lines: [], previousProse: "the .env"))
        #expect(!ComposeClaimReader.isDotEnv(tag: "", info: "", lines: ["echo"], previousProse: "the .env"))
        #expect(!ComposeClaimReader.isDotEnv(tag: "python", info: "python", lines: ["A=1"], previousProse: ".env"))
        #expect(ComposeClaimReader.isDotEnv(tag: "", info: "", lines: ["A=1"], previousProse: "the .env file"))
    }

    @Test func severalComposeFiles() {
        let base = block("yaml:compose.yaml", "services:", "  web:", "    image: x")
        let override = block("yaml:compose.override.yaml", "services:", "  web:", "    build: .",
                             "    ports: [\"80:80\"]")
        let merged = ComposeClaimReader.scene(AnswerBlocks.split(base + override), text: base + override,
                                              earlier: Scene())
        #expect(merged.reading == .unreadable("the answer merges several compose files, which this reader does not do"))
        let twice = yaml("services:", "  web:", "    image: x") + yaml("services:", "  api:", "    image: y")
        let last = ComposeClaimReader.scene(AnswerBlocks.split(twice), text: twice, earlier: Scene())
        #expect(last.project?.services.map(\.name) == ["api"])
        let unclosed = "\(fence)yaml\nservices:\n  web:\n    image: x\n"
        #expect(ComposeClaimReader.scene(AnswerBlocks.split(unclosed), text: unclosed, earlier: Scene()).project != nil)
        #expect(AnswerBlocks.tag("yaml:compose.yaml") == "yaml")
    }

    @Test func dependencyLines() {
        let answer = yaml("services:", "  app:", "    image: x", "    depends_on:", "      db:",
                          "        condition: service_healthy", "      cache:", "        condition: service_started",
                          "  db:", "    image: postgres", "  worker:", "    image: y", "    depends_on: [db]")
        let report = checker.check(answer)
        #expect(report.findings.map(\.claim.subject) == [.line(.healthyWithoutHealthcheck("db"), service: "app"),
                                                         .line(.undefinedDependency("cache"), service: "app")])
        // A fragment may leave out a service, so an undefined dependency is unchecked, not wrong.
        #expect(report.verdict == .caution && report.findings[1].severity == .unchecked)
        #expect(ComposeClaimChecker(policy: .lenient).check(answer).findings.isEmpty)
        #expect(report.findings.allSatisfy { !$0.claim.isExplicit })
    }

    @Test func oneMistakeOneFinding() {
        let published = stack.replacingOccurrences(of: "@db:5432/app", with: "@db:5433/app")
        let stated = checker.check(published + "Inside the network, the `app` service reaches Postgres at `db:5433`.")
        #expect(stated.findings.count == 1 && stated.findings[0].claim.isExplicit)
        let alone = checker.check(published)
        #expect(alone.findings.count == 1 && !alone.findings[0].claim.isExplicit)
        let twice = checker.check(stack + "Containers talk to each other on `localhost`, so `app` connects to "
            + "`localhost:5432`.")
        #expect(twice.findings.count == 1)
    }

    @Test func report() {
        let wrong = checker.check(stack + "`depends_on` makes sure the database is ready before the app starts.")
        #expect(wrong.note?.hasPrefix("Compose check: ") == true)
        #expect(wrong.feedback?.contains("- `depends_on` waits only") == true)
        #expect(wrong.summary == "1 claim checked, 0 hold, 1 wrong")
        let none = checker.check("Hello.")
        #expect(none.verdict == .noClaims && none.note == nil && none.feedback == nil)
        #expect(none.summary == "no claims about a compose project")
        let mixed = checker.check(stack + "Open `localhost:8080` in your browser. Open `localhost:9999` in your browser.")
        #expect(mixed.verdict == .unchecked && mixed.summary == "2 claims checked, 1 hold, 1 unchecked")
        let caution = checker.check(yaml("services:", "  api:", "    image: x", "    ports: [\"8000:8000\"]", "  ui:",
                                         "    image: y", "    environment:", "      API: localhost:8000"))
        #expect(caution.verdict == .caution && caution.summary.contains("1 to check"))
        #expect(ComposeReport(findings: []).flagged.isEmpty)
    }

    @Test func ledger() async {
        let ledger = ComposeLedger()
        let first = await ledger.review(stack + "Containers talk to each other on `localhost`, so `app` connects to "
            + "`localhost:5432`.")
        #expect(first.verdict == .wrong && first.repeatedCount == 0)
        let second = await ledger.review("Right, keep `localhost:5432` for the `app` service; it connects there.")
        #expect(second.repeatedCount == 1 && second.note?.contains("stated again") == true)
        #expect(second.summary.contains("1 repeated"))
        let unrelated = await ledger.review("Open `localhost:8080` in your browser.")
        #expect(unrelated.verdict == .noClaims)
        let statistics = await ledger.statistics
        #expect(statistics == .init(reviews: 3, claims: 2, flagged: 2, repeated: 1))
        await ledger.forget()
        let fresh = await ledger.review("Right, keep `localhost:5432` for the `app` service; it connects there.")
        #expect(fresh.verdict == .noClaims)
    }
}
