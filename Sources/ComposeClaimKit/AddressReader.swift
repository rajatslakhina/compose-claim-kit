/// Reads `host:port` addresses (bare or inside a URL) from a sentence or a compose value.
enum AddressReader {
    struct Found: Hashable {
        let host: String
        let port: Int
    }

    /// Every address in the text whose host is a loopback name or a name the project answers to.
    static func addresses(in text: String, project: ComposeProject?) -> [Found] {
        let separators = Set(" \t`\"'(),;<>")
        let images = Set(project?.services.compactMap(\.image) ?? [])
        var found: [Found] = []
        var previous = ""
        for raw in text.split(whereSeparator: { separators.contains($0) }) {
            defer { previous = raw.folded }
            // `postgres:16` after "image" or as a service's image is an image reference, not an address.
            guard !images.contains(String(raw)), !["image", "image:", "from"].contains(previous),
                  let address = parse(String(raw)) else { continue }
            let known = ComposeClaim.Address(vantage: .host, host: address.host, port: address.port).isLoopback
                || project?.service(address.host) != nil
            if known, !found.contains(address) { found.append(address) }
        }
        return found
    }

    /// `localhost:8080`, `http://db:5432/app`, `postgres://u:p@db:5432/x`, `URL=redis://cache:6379`.
    static func parse(_ token: String) -> Found? {
        var text = token.trimmingCharacters(in: .init(charactersIn: ".:!?"))
        if let equals = text.firstIndex(of: "="), text[..<equals].allSatisfy(Names.isNameCharacter) {
            text = String(text[text.index(after: equals)...])
        }
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let host = String(text[..<colon])
        guard let port = Int(text[text.index(after: colon)...]), (1...65535).contains(port), !host.isEmpty,
              host == "[::1]" || host.allSatisfy({ $0.isLetter || $0.isNumber || ".-_".contains($0) }),
              host.contains(where: \.isLetter) || host.contains(".") else { return nil }
        return Found(host: host, port: port)
    }

    /// The claims a prose sentence makes about addresses.
    static func claims(_ sentence: String, scene: Scene) -> [ComposeClaim] {
        guard scene.reading != nil else { return [] }
        let prose = Cues.prose(sentence)
        guard !Cues.blocked(prose) else { return [] }
        let project = scene.project
        let words = sentence.replacingOccurrences(of: "`", with: " ").folded
        let named = project?.services.filter { service in
            ([service.name] + service.aliases).contains { Words.contains(words, $0.folded) }
        } ?? []
        // "container port 80" says which side of a mapping, not where the address is used from.
        let cues = prose.replacingOccurrences(of: "container port", with: "").replacingOccurrences(of: "host port",
                                                                                                    with: "")
        let fromContainer = Words.containsAny(cues, Cues.container)
        let fromHost = Words.containsAny(cues, Cues.host)
        var claims: [ComposeClaim] = []
        for address in addresses(in: sentence, project: project) {
            let loopback = ComposeClaim.Address(vantage: .host, host: address.host, port: address.port).isLoopback
            let vantage: ComposeVantage
            if loopback {
                if named.count == 1, fromContainer {
                    vantage = .service(named[0].name)
                } else if fromHost, !fromContainer {
                    vantage = .host
                } else {
                    continue
                }
            } else {
                if fromHost, !fromContainer { continue }
                let other = named.filter { !$0.answers(to: address.host) }
                vantage = .service(other.count == 1 ? other[0].name : nil)
            }
            let claim = ComposeClaim.Address(vantage: vantage, host: address.host, port: address.port)
            claims.append(ComposeClaim(subject: .address(claim), sentence: sentence, scene: scene))
        }
        return claims
    }

    /// Addresses in each service's `environment:` values, judged as used from that service.
    static func lines(_ scene: Scene) -> [ComposeClaim] {
        guard let project = scene.project else { return [] }
        var claims: [ComposeClaim] = []
        for service in project.services {
            for variable in service.environment {
                for address in addresses(in: variable.value ?? "", project: project) {
                    let claim = ComposeClaim.Address(vantage: .service(service.name), host: address.host,
                                                     port: address.port, variable: variable.name)
                    let sentence = "\(service.name): \(variable.name)=\(variable.value ?? "")"
                    claims.append(ComposeClaim(subject: .address(claim), sentence: sentence, scene: scene))
                }
            }
        }
        return claims
    }
}

/// "`8080:80` maps host port 8080 to container port 80": a host port and a container port named in one sentence.
enum MappingReader {
    static let hostPlaces = ["on the host", "on your machine", "on the host's"]
    static let containerPlaces = ["in the container", "inside the container", "of the container"]

    static func claims(_ sentence: String, scene: Scene) -> [ComposeClaim] {
        guard scene.reading != nil else { return [] }
        let prose = sentence.replacingOccurrences(of: "`", with: " ").folded
        guard !Cues.blocked(prose) else { return [] }
        let words = prose.split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init)
        var host: Int?
        var container: Int?
        for (index, word) in words.enumerated() {
            guard let number = Int(word) else { continue }
            let before = words[max(0, index - 2)..<index].joined(separator: " ")
            let after = words[(index + 1)..<min(words.count, index + 4)].joined(separator: " ")
            if before.hasSuffix("host port") || hostPlaces.contains(where: after.hasPrefix) {
                host = host ?? number
            } else if before.hasSuffix("container port") || containerPlaces.contains(where: after.hasPrefix) {
                container = container ?? number
            }
        }
        guard let host, let container else { return [] }
        return [ComposeClaim(subject: .mapping(published: host, target: container), sentence: sentence, scene: scene)]
    }
}
