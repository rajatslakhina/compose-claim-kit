/// One entry of a service's `ports:` after compose has read it: an optional host address, the host port (or range
/// of host ports, one of which Docker picks) and the container port.
public struct PortMapping: Sendable, Hashable {
    public let hostIP: String?
    /// The host port or ports; `nil` when Docker picks a free one at start.
    public let published: ClosedRange<Int>?
    public let target: Int
    public let proto: String

    public init(hostIP: String? = nil, published: ClosedRange<Int>?, target: Int, proto: String = "tcp") {
        self.hostIP = hostIP
        self.published = published
        self.target = target
        self.proto = proto
    }

    struct Invalid: Error, Equatable {
        let text: String
    }

    /// Reachable from the host's own `localhost`: published on every address, or on a loopback one.
    var isOnLoopback: Bool {
        guard let hostIP else { return true }
        return ["0.0.0.0", "127.0.0.1", "::", "::1", "localhost"].contains(hostIP)
    }

    /// `[host_ip:][published[-end]:]target[-end][/protocol]`, as compose's short syntax reads it, one mapping per
    /// container port (`8000-8002:9000-9002` is three).
    static func parse(short text: String) throws(Invalid) -> [PortMapping] {
        var spec = text.trimmed
        var proto = "tcp"
        if let slash = spec.lastIndex(of: "/") {
            proto = String(spec[spec.index(after: slash)...]).lowercased()
            spec = String(spec[..<slash])
            guard ["tcp", "udp", "sctp"].contains(proto) else { throw Invalid(text: text) }
        }
        var hostIP: String?
        if spec.hasPrefix("[") {
            guard let close = spec.range(of: "]:") else { throw Invalid(text: text) }
            hostIP = String(spec[spec.index(after: spec.startIndex)..<close.lowerBound])
            spec = String(spec[close.upperBound...])
        }
        var parts = spec.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3, hostIP == nil { hostIP = parts.removeFirst() }
        guard (1...2).contains(parts.count), let targets = range(parts[parts.count - 1]) else {
            throw Invalid(text: text)
        }
        let hosts: ClosedRange<Int>?
        // An empty host side, or `0`, lets Docker pick the host port.
        if parts.count == 2, !parts[0].isEmpty, parts[0] != "0" {
            guard let parsed = range(parts[0]) else { throw Invalid(text: text) }
            hosts = parsed
        } else {
            hosts = nil
        }
        return try expand(hostIP: hostIP, hosts: hosts, targets: targets, proto: proto, text: text)
    }

    static func expand(hostIP: String?, hosts: ClosedRange<Int>?, targets: ClosedRange<Int>, proto: String,
                       text: String) throws(Invalid) -> [PortMapping] {
        guard let hosts else {
            return targets.map { PortMapping(hostIP: hostIP, published: nil, target: $0, proto: proto) }
        }
        if targets.count == 1 {
            return [PortMapping(hostIP: hostIP, published: hosts, target: targets.lowerBound, proto: proto)]
        }
        guard hosts.count == targets.count else { throw Invalid(text: text) }
        return zip(hosts, targets).map { PortMapping(hostIP: hostIP, published: $0...$0, target: $1, proto: proto) }
    }

    /// `80` or `8000-8002`, every port between 1 and 65535.
    static func range(_ text: String) -> ClosedRange<Int>? {
        let bounds = text.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...2).contains(bounds.count), let low = bounds[0], let high = bounds[bounds.count - 1],
              1 <= low, low <= high, high <= 65535 else { return nil }
        return low...high
    }

    /// The long syntax: `target`, `published`, `host_ip`, `protocol`.
    static func parse(long node: ComposeNode) throws(Invalid) -> [PortMapping] {
        guard let target = node["target"]?.text.flatMap(Int.init), (1...65535).contains(target) else {
            throw Invalid(text: "a long-syntax port without a valid target")
        }
        var hosts: ClosedRange<Int>?
        if let published = node["published"]?.text {
            guard let parsed = range(published) else { throw Invalid(text: published) }
            hosts = parsed
        }
        let proto = node["protocol"]?.text?.lowercased() ?? "tcp"
        return [PortMapping(hostIP: node["host_ip"]?.text, published: hosts, target: target, proto: proto)]
    }

    /// `8080:80`, `127.0.0.1:5432:5432`, or `80` when Docker picks the host port.
    public var display: String {
        let host = published.map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound)-\($0.upperBound)" }
        let ip = hostIP.map { $0.contains(":") ? "[\($0)]:" : "\($0):" } ?? ""
        let suffix = proto == "tcp" ? "" : "/\(proto)"
        guard let host else { return ip.isEmpty ? "\(target)\(suffix)" : "\(ip):\(target)\(suffix)" }
        return "\(ip)\(host):\(target)\(suffix)"
    }
}
