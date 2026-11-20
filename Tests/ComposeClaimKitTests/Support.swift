@testable import ComposeClaimKit

let fence = "```"

func yaml(_ lines: String...) -> String {
    "\(fence)yaml\n" + lines.joined(separator: "\n") + "\n\(fence)\n"
}

func block(_ info: String, _ lines: String...) -> String {
    "\(fence)\(info)\n" + lines.joined(separator: "\n") + "\n\(fence)\n"
}

/// The project a compose text reads to, or `nil` with the reason recorded.
func project(_ source: String, _ variables: Variables = Variables()) -> ComposeProject? {
    if case let .project(project) = ComposeProject.read(source, variables: variables) { return project }
    return nil
}

func reason(_ source: String) -> String? {
    if case let .unreadable(reason) = ComposeProject.read(source) { return reason }
    return nil
}

func scene(_ source: String, _ variables: Variables = Variables()) -> Scene {
    Scene(reading: ComposeProject.read(source, variables: variables), variables: variables)
}

func judge(_ subject: ComposeClaim.Subject, _ scene: Scene, policy: ComposePolicy = .standard) -> ComposeFinding {
    ComposeEvaluator(policy: policy).judge(ComposeClaim(subject: subject, sentence: "s", scene: scene))
}

let webAndDB = """
services:
  web:
    image: nginx:1.27
    ports:
      - "8080:80"
  app:
    build: .
    environment:
      DATABASE_URL: postgres://app:secret@db:5432/app
    depends_on:
      - db
  db:
    image: postgres:16
    ports:
      - "5433:5432"
"""

let stack = "\(fence)yaml\n" + webAndDB + "\n\(fence)\n"
