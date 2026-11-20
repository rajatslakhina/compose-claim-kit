import Testing
@testable import ComposeClaimKit

@Suite("Reading a compose project")
struct ProjectTests {
    @Test func services() throws {
        let read = try #require(project("""
        services:
          app:
            image: myapp
            container_name: my-app
            hostname: apphost
            expose: ["9000", 9100-9101]
            environment:
              - A=1
              - FROM_SHELL
              - MISSING
            depends_on:
              db:
                condition: service_healthy
              cache: {}
            healthcheck:
              test: ["CMD", "true"]
          db:
            image: docker.io/library/postgres:16-alpine
            healthcheck:
              disable: true
            network_mode: host
          cache:
            image: redis@sha256:abc
            extends:
              file: base.yaml
              service: cache
            depends_on: worker
        """.replacingOccurrences(of: "cache: {}", with: "cache:"), Variables(shell: ["FROM_SHELL": "s"])))
        let app = try #require(read.service("my-app"))
        #expect(app.name == "app" && read.service("apphost") == app && read.service("nope") == nil)
        #expect(app.exposed == [9000, 9100, 9101])
        #expect(app.environment == [.init(name: "A", value: "1"), .init(name: "FROM_SHELL", value: "s"),
                                    .init(name: "MISSING", value: nil)])
        #expect(app.dependsOn == [.init(name: "db", condition: "service_healthy"),
                                  .init(name: "cache", condition: "service_started")])
        #expect(app.hasHealthcheck)
        let db = try #require(read.service("db"))
        #expect(!db.hasHealthcheck && db.hasCustomNetworking && db.containerPorts == [5432])
        let cache = try #require(read.service("cache"))
        #expect(cache.opaque != nil && cache.containerPorts == [6379] && cache.dependsOn.map(\.name) == ["worker"])
    }

    @Test func imagePorts() {
        #expect(ImagePorts.ports("postgres") == [5432])
        #expect(ImagePorts.ports("library/mysql:8") == [3306, 33060])
        #expect(ImagePorts.ports("bitnami/postgresql") == [])
        #expect(ImagePorts.ports("ghcr.io/org/redis") == [])
        #expect(ImagePorts.ports("custom") == [])
        #expect(ImagePorts.ports(nil) == [])
    }

    @Test func portsThatDependOnVariables() throws {
        let read = try #require(project("services:\n  web:\n    image: x\n    ports:\n      - \"${PORT:-8080}:80\"\n"))
        #expect(read.services[0].portsAssumeUnset == ["PORT"])
        let known = try #require(project("services:\n  web:\n    image: x\n    ports:\n      - \"${PORT}:80\"\n",
                                         Variables(shell: ["PORT": "9000"])))
        #expect(known.services[0].ports.map(\.display) == ["9000:80"])
        let long = try #require(project("services:\n  web:\n    image: x\n    ports:\n      - target: 80\n"
            + "        published: ${P:-81}\n"))
        #expect(long.services[0].ports.map(\.display) == ["81:80"])
        let empty = try #require(project("services:\n  web:\n    image: x\n    ports:\n      - target: 80\n"
            + "        published:\n"))
        #expect(empty.services[0].ports.map(\.display) == ["80"])
    }

    @Test(arguments: [
        ("services:\n  a:\n    image: &x y\n", "an anchor"),
        ("version: '3'\n", "no `services:`"),
        ("services:\n  a:\n    image: ${TAG:?set TAG first}\n", "set TAG first"),
        ("services:\n  a:\n    image: ${TAG?}\n", "required variable TAG is missing a value"),
        ("services:\n  a:\n    ports:\n      - \"8000-8001:9000-9002\"\n", "refuses the port"),
        ("services:\n  a:\n    ports:\n      - target: 0\n", "refuses the port"),
        ("services:\n  a:\n    ports:\n      - \"${P:?}:80\"\n", "required variable P"),
        ("services:\n  a:\n    ports:\n      - target: ${T:?no target}\n", "no target"),
        ("services:\n  a:\n    ports:\n      - \"$\"\n", "substitution"),
        ("services:\n  a:\n    expose: [x]\n", "refuses the port"),
        ("services:\n  a:\n    ports:\n      -\n        - 80\n", "neither text nor a mapping"),
        ("services:\n  a:\n    ports:\n      - - 80\n", "a sequence inside a sequence item"),
        ("services:\n  a:\n    environment:\n      A: $\n", "substitution"),
        ("services:\n  a:\n    environment: [\"$\"]\n", "substitution"),
        ("services:\n  a:\n    depends_on:\n      b:\n        condition: $\n", "substitution"),
        ("services:\n  a:\n    depends_on: [\"$\"]\n", "substitution")
    ])
    func unreadable(source: String, why: String) throws {
        let reason = try #require(unreadableReason(source))
        #expect(reason.contains(why), "\(reason)")
    }

    @Test func looksLikeCompose() {
        #expect(ComposeProject.looksLikeCompose(["services:", "  web:", "    image: x"]))
        #expect(ComposeProject.looksLikeCompose(["services: # the stack", "  web:", "    build: ."]))
        #expect(!ComposeProject.looksLikeCompose(["services:", "  web:", "image: x"]))
        #expect(!ComposeProject.looksLikeCompose(["on: push", "jobs:", "  t:", "    services:"]))
        #expect(!ComposeProject.looksLikeCompose(["apiVersion: v1", "kind: Service", "services:"]))
        #expect(!ComposeProject.looksLikeCompose(["web:", "  image: x"]))
    }

    @Test func scene() {
        let empty = Scene()
        #expect(empty.project == nil && empty.reading == nil)
        #expect(sceneOf(webAndDB).project?.services.count == 3)
    }
}
