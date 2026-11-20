/// One service of a compose file, with what the claims need: its names on the network, its ports, its environment
/// and what it waits for.
public struct ComposeService: Sendable, Hashable {
    public struct Dependency: Sendable, Hashable {
        public let name: String
        /// `service_started` (the default), `service_healthy` or `service_completed_successfully`.
        public let condition: String
    }

    public struct Variable: Sendable, Hashable {
        public let name: String
        /// `nil` for `- NAME` or `NAME:` with no value that neither the shell nor `.env` sets.
        public let value: String?
    }

    public let name: String
    public var image: String?
    /// `container_name` and `hostname`, which other containers can also use.
    public var aliases: [String] = []
    public var ports: [PortMapping] = []
    /// `expose:` ports, open to other containers only.
    public var exposed: [Int] = []
    public var environment: [Variable] = []
    public var dependsOn: [Dependency] = []
    public var hasHealthcheck = false
    /// `network_mode`, `networks:`, `extra_hosts` or `links`: reachability is not the default network's.
    public var hasCustomNetworking = false
    /// Why nothing about the service can be checked (`extends` pulls in another file), if so.
    public var opaque: String?
    /// The `ports:` text used a variable the conversation does not set, so the mappings assume it unset.
    public var portsAssumeUnset: Set<String> = []

    init(name: String) {
        self.name = name
    }

    /// The ports the container itself listens on, as far as the file says, plus the port its image is known to
    /// listen on (an official image's `EXPOSE`).
    public var containerPorts: Set<Int> {
        Set(ports.map(\.target) + exposed + ImagePorts.ports(image))
    }

    func answers(to host: String) -> Bool {
        host == name || aliases.contains(host)
    }
}

/// A compose file after compose's own reading: YAML, then variable substitution, then the short syntaxes.
public struct ComposeProject: Sendable, Hashable {
    public let services: [ComposeService]

    public init(services: [ComposeService]) {
        self.services = services
    }

    public func service(_ host: String) -> ComposeService? {
        services.first { $0.answers(to: host) }
    }

    /// The project, or why it cannot be read.
    public enum Reading: Sendable, Hashable {
        case project(ComposeProject)
        case unreadable(String)
    }

    /// Whether the text is a compose file: a top-level `services:` and nothing marking another tool's YAML (GitHub
    /// Actions' `jobs:`, Kubernetes' `apiVersion:`).
    static func looksLikeCompose(_ lines: [String]) -> Bool {
        let keys = lines.filter { !$0.hasPrefix(" ") && !$0.hasPrefix("#") }
            .compactMap { ComposeYAML.key(ComposeYAML.stripComment($0).trimmed)?.0 }
        let others = ["jobs", "on", "apiVersion", "kind", "steps"]
        return keys.contains("services") && !keys.contains { others.contains($0) }
    }

    public static func read(_ source: String, variables: Variables = Variables()) -> Reading {
        let root: ComposeNode
        do {
            root = try ComposeYAML.parse(source)
        } catch {
            return .unreadable("the compose file uses " + error.reason)
        }
        guard let entries = root["services"]?.entries else {
            return .unreadable("the compose file has no `services:` mapping")
        }
        var services: [ComposeService] = []
        for entry in entries {
            do {
                services.append(try ServiceReader(variables: variables).read(entry.key, entry.value))
            } catch let .required(name, message) {
                let why = message.isEmpty ? "required variable \(name) is missing a value" : message
                return .unreadable("`docker compose` stops before starting anything: \(why)")
            } catch let .ports(text) {
                return .unreadable("`docker compose` refuses the port `\(text)`")
            } catch {
                return .unreadable("service `\(entry.key)` uses variable substitution this reader does not follow")
            }
        }
        return .project(ComposeProject(services: services))
    }
}

struct ServiceReader {
    enum Failure: Error {
        case required(String, String)
        case ports(String)
        case malformed
    }

    let variables: Variables

    func resolve(_ text: String, unknown: inout Set<String>) throws(Failure) -> String {
        do {
            let result = try Interpolation.resolve(text, variables)
            unknown.formUnion(result.unknown)
            return result.value
        } catch let .required(name, message) {
            throw .required(name, message)
        } catch {
            throw .malformed
        }
    }

    func text(_ node: ComposeNode?) throws(Failure) -> String? {
        var unknown: Set<String> = []
        return try node?.text.map { text throws(Failure) in try resolve(text, unknown: &unknown) }
    }

    func list(_ node: ComposeNode?) throws(Failure) -> [String] {
        if let single = try text(node) { return [single] }
        var values: [String] = []
        for item in node?.items ?? [] {
            if let value = try text(item) { values.append(value) }
        }
        return values
    }

    func read(_ name: String, _ node: ComposeNode) throws(Failure) -> ComposeService {
        var service = ComposeService(name: name)
        service.image = try text(node["image"])
        for key in ["container_name", "hostname"] {
            if let alias = try text(node[key]) { service.aliases.append(alias) }
        }
        try readPorts(node, into: &service)
        for item in node["expose"]?.items ?? [] {
            guard let port = try text(item), let range = PortMapping.range(port) else { throw .ports("expose") }
            service.exposed += Array(range)
        }
        service.environment = try environment(node["environment"])
        service.dependsOn = try dependencies(node["depends_on"])
        if let check = node["healthcheck"] {
            service.hasHealthcheck = try text(check["disable"]) != "true"
        }
        service.hasCustomNetworking = ["network_mode", "networks", "extra_hosts", "links"].contains { node[$0] != nil }
        if node["extends"] != nil { service.opaque = "it `extends` a service this conversation does not show" }
        return service
    }

    func readPorts(_ node: ComposeNode, into service: inout ComposeService) throws(Failure) {
        for item in node["ports"]?.items ?? [] {
            do {
                if let short = item.text {
                    var unknown: Set<String> = []
                    service.ports += try PortMapping.parse(short: try resolve(short, unknown: &unknown))
                    service.portsAssumeUnset.formUnion(unknown)
                } else {
                    service.ports += try PortMapping.parse(long: try interpolated(item))
                }
            } catch let error as PortMapping.Invalid {
                throw .ports(error.text)
            } catch let error as Failure {
                throw error
            } catch {
                throw .malformed
            }
        }
    }

    /// A mapping with every scalar value substituted.
    func interpolated(_ node: ComposeNode) throws(Failure) -> ComposeNode {
        var entries: [ComposeEntry] = []
        for entry in node.entries ?? [] {
            entries.append(ComposeEntry(key: entry.key, value: try text(entry.value).map(ComposeNode.scalar) ?? .null))
        }
        return .map(entries)
    }

    /// `NAME: value` or `- NAME=value`; a name with no value takes the shell's (or `.env`'s) value, if any.
    func environment(_ node: ComposeNode?) throws(Failure) -> [ComposeService.Variable] {
        let pairs: [(String, String?)]
        if let entries = node?.entries {
            pairs = try entries.map { entry throws(Failure) in (entry.key, try text(entry.value)) }
        } else {
            pairs = try list(node).map { item in
                guard let equals = item.firstIndex(of: "=") else { return (item, nil) }
                return (String(item[..<equals]), String(item[item.index(after: equals)...]))
            }
        }
        return pairs.map { name, value in
            let inherited = variables.unread.contains(name) ? nil : variables.value(name, dotEnvFirst: false)
            return ComposeService.Variable(name: name, value: value ?? inherited)
        }
    }

    func dependencies(_ node: ComposeNode?) throws(Failure) -> [ComposeService.Dependency] {
        if let entries = node?.entries {
            return try entries.map { entry throws(Failure) in
                let condition = try text(entry.value["condition"]) ?? "service_started"
                return ComposeService.Dependency(name: entry.key, condition: condition)
            }
        }
        return try list(node).map { ComposeService.Dependency(name: $0, condition: "service_started") }
    }
}
