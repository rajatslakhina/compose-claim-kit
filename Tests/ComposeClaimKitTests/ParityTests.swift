import Foundation
import Testing
@testable import ComposeClaimKit

/// Every case of `Scripts/parity.py`, as `docker compose config --format json` read it, against this kit's reading.
@Suite("Parity with docker compose config")
struct ParityTests {
    struct Expected: Decodable {
        struct Service: Decodable {
            let ports: [[Port]]
            let expose: [String]
            let environment: [String: String?]
        }

        enum Port: Decodable, Equatable {
            case text(String)
            case number(Int)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let number = try? container.decode(Int.self) {
                    self = .number(number)
                } else {
                    self = .text(try container.decode(String.self))
                }
            }
        }

        let error: Bool
        let services: [String: Service]?
    }

    static func ours(_ mapping: PortMapping) -> [Expected.Port] {
        let published = mapping.published.map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)-\($0.upperBound)" }
        return [.text(mapping.hostIP ?? ""), .text(published ?? ""), .number(mapping.target), .text(mapping.proto)]
    }

    @Test func fixtureHasEveryCase() {
        #expect(parityCases.count == 73)
    }

    @Test(arguments: parityCases.map(\.name))
    func matches(name: String) throws {
        let item = try #require(parityCases.first { $0.name == name })
        let expected = try JSONDecoder().decode(Expected.self, from: Data(item.expected.utf8))
        let parsed = item.dotEnv.map { EnvFile.parse($0.components(separatedBy: "\n")) }
        let variables = Variables(shell: item.shell, dotEnv: parsed?.values ?? [:], unread: parsed?.unread ?? [])
        let reading = ComposeProject.read(item.compose, variables: variables)
        if expected.error {
            let refused: Bool
            if case .unreadable = reading {
                refused = true
            } else {
                // compose refuses a dependency on an undefined service; the kit reads the file and flags the line.
                let lines = ComposeClaimReader.dependencyLines(Scene(reading: reading, variables: variables))
                refused = lines.contains { if case .line(.undefinedDependency, _) = $0.subject { true } else { false } }
            }
            #expect(refused, "compose refuses \(name)")
            return
        }
        guard case let .project(project) = reading else {
            // Only YAML this reader declines (an anchor and a merge key) may be unreadable where compose is not.
            #expect(name == "anchor", "\(name): \(reading)")
            return
        }
        let services = try #require(expected.services)
        #expect(Set(project.services.map(\.name)) == Set(services.keys))
        for service in project.services {
            let theirs = try #require(services[service.name])
            // compose keeps a host port of `0`, which, like none, lets Docker pick one.
            let ports = theirs.ports.map { $0.map { $0 == .text("0") ? .text("") : $0 } }
            #expect(service.ports.map(Self.ours) == ports, "\(name) ports")
            let exposed = theirs.expose.flatMap { PortMapping.range($0).map(Array.init) ?? [] }
            #expect(service.exposed == exposed, "\(name) expose")
            let environment = Dictionary(uniqueKeysWithValues: service.environment.map { ($0.name, $0.value) })
            #expect(environment == theirs.environment, "\(name) environment")
        }
    }
}
