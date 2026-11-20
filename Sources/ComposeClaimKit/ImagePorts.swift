/// The ports official images `EXPOSE`, for services whose file does not list them (`image: postgres:16`).
enum ImagePorts {
    static let known: [String: [Int]] = [
        "postgres": [5432], "mysql": [3306, 33060], "mariadb": [3306], "redis": [6379], "mongo": [27017],
        "memcached": [11211], "rabbitmq": [4369, 5671, 5672, 15691, 15692, 25672], "nginx": [80], "httpd": [80]
    ]

    /// `postgres:16-alpine`, `library/postgres`, `docker.io/library/redis:7` name an official image; a registry
    /// host or an organisation (`bitnami/postgresql`) does not.
    static func ports(_ image: String?) -> [Int] {
        guard var name = image?.lowercased() else { return [] }
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
        var parts = name.split(separator: "/").map(String.init)
        if parts.first == "docker.io" { parts.removeFirst() }
        if parts.count == 2, parts[0] == "library" { parts.removeFirst() }
        guard parts.count == 1 else { return [] }
        let repository = parts[0].split(separator: ":").first.map(String.init) ?? ""
        return known[repository] ?? []
    }
}
