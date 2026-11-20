import Testing
@testable import ComposeClaimKit

/// Correct answers that contrast two things without a negation.
@Suite("Contrast probes")
struct ContrastProbeTests {
    let checker = ComposeClaimChecker()

    @Test(arguments: [
        "`expose` makes the port available to other containers, while `ports` publishes it to the host.",
        "Containers connect to each other by service name, and you connect from the host via `localhost:5433`.",
        "The values in `.env` are passed to the container through `environment:`."
    ])
    func stackAnswers(answer: String) {
        let report = checker.check(stack + answer)
        #expect(report.flagged.isEmpty, "\(answer): \(report.corrections)")
    }

    @Test func browserCallsAPI() {
        let answer = yaml("services:", "  frontend:", "    build: ./web", "    ports: [\"3000:3000\"]", "  backend:",
                          "    build: ./api", "    ports: [\"8000:8000\"]")
            + "The `frontend` runs in your browser and calls the API at `http://localhost:8000`."
        let report = checker.check(answer)
        #expect(report.flagged.isEmpty, "\(report.corrections)")
    }
}
