import Testing
@testable import ComposeClaimKit

@Suite("Port mappings")
struct PortTests {
    @Test(arguments: [
        ("8080:80", ["8080:80"]), ("80", ["80"]), ("127.0.0.1:5432:5432", ["127.0.0.1:5432:5432"]),
        ("8000-8001:9000-9001", ["8000:9000", "8001:9001"]), ("53:53/udp", ["53:53/udp"]),
        ("9090-9091:8080", ["9090-9091:8080"]), ("[::1]:8081:81", ["[::1]:8081:81"]),
        ("127.0.0.1::80", ["127.0.0.1::80"]), ("3000-3001", ["3000", "3001"]), ("0:80", ["80"]),
        ("8080:80/SCTP", ["8080:80/sctp"])
    ])
    func short(text: String, displays: [String]) throws {
        #expect(try PortMapping.parse(short: text).map(\.display) == displays)
    }

    @Test(arguments: ["8000-8001:9000-9002", "80/xyz", "70000:80", "1.2.3.4:5:6:7", "[::1:80", "[::1]:1:2:3",
                      "a:80", "80:", "9-8", "8080:80-81"])
    func invalid(text: String) {
        #expect(throws: PortMapping.Invalid.self) { try PortMapping.parse(short: text) }
    }

    @Test func long() throws {
        let mapping = try PortMapping.parse(long: .map([
            ComposeEntry(key: "target", value: .scalar("80")), ComposeEntry(key: "published", value: .scalar("8080")),
            ComposeEntry(key: "host_ip", value: .scalar("127.0.0.1")), ComposeEntry(key: "protocol", value: .scalar("UDP"))
        ]))
        #expect(mapping.map(\.display) == ["127.0.0.1:8080:80/udp"])
        #expect(try PortMapping.parse(long: .map([ComposeEntry(key: "target", value: .scalar("443"))])).map(\.display)
            == ["443"])
        #expect(throws: PortMapping.Invalid.self) { try PortMapping.parse(long: .map([])) }
        #expect(throws: PortMapping.Invalid.self) {
            try PortMapping.parse(long: .map([ComposeEntry(key: "target", value: .scalar("80")),
                                              ComposeEntry(key: "published", value: .scalar("x"))]))
        }
    }

    @Test func loopback() {
        #expect(PortMapping(published: 1...1, target: 1).isOnLoopback)
        #expect(PortMapping(hostIP: "127.0.0.1", published: 1...1, target: 1).isOnLoopback)
        #expect(!PortMapping(hostIP: "192.168.1.5", published: 1...1, target: 1).isOnLoopback)
        #expect(PortMapping.range("0") == nil && PortMapping.range("1-2-3") == nil)
    }
}
