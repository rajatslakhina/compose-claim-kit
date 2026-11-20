/// One thing an answer says, or shows in its compose file, about how a compose project behaves.
public struct ComposeClaim: Sendable, Hashable {
    public enum Subject: Sendable, Hashable {
        /// "open `localhost:8080`" or "`app` connects to `db:5432`": an address and where it is used from.
        case address(Address)
        /// "`8080:80` maps host port 8080 to container port 80".
        case mapping(published: Int, target: Int)
        /// "with `TAG` unset, `${TAG:-latest}` becomes `latest`".
        case resolves(Resolves)
        /// A general statement about how compose works.
        case statement(Statement)
        /// Something in the compose file that does not do what it looks like.
        case line(Line, service: String)
    }

    public struct Address: Sendable, Hashable {
        public let vantage: ComposeVantage
        public let host: String
        public let port: Int
        /// The environment variable the address was found in, for an address the compose file sets.
        public let variable: String?
        /// The URL scheme it was written with (`http`, `postgres`), if any.
        public let scheme: String?

        public init(vantage: ComposeVantage, host: String, port: Int, variable: String? = nil, scheme: String? = nil) {
            self.vantage = vantage
            self.host = host
            self.port = port
            self.variable = variable
            self.scheme = scheme
        }

        /// A browser reads `http(s)` and `ws(s)` URLs; databases and queues are reached by the process itself.
        var isWeb: Bool {
            ["http", "https", "ws", "wss"].contains(scheme ?? "")
        }

        var isLoopback: Bool {
            ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
        }
    }

    public struct Resolves: Sendable, Hashable {
        public let expression: String
        public let condition: ResolveCondition?
        public let claimed: ResolveOutcome
    }

    public enum Statement: String, Sendable, Hashable, CaseIterable {
        /// `depends_on` orders start-up and does not wait for readiness. Holds.
        case dependsOnOrdersStart
        /// `depends_on` waits until the dependency is ready. Wrong without `condition: service_healthy`.
        case dependsOnWaitsForReady
        /// `.env` feeds substitution in the compose file and is not passed into containers. Holds.
        case dotEnvForSubstitution
        /// Variables in `.env` are set inside the containers. Wrong: only `env_file:` or `environment:` do that.
        case dotEnvReachesContainer
        /// The shell's environment wins over `.env`. Holds.
        case shellBeatsDotEnv
        /// `.env` wins over the shell's environment. Wrong.
        case dotEnvBeatsShell
        /// `environment:` wins over `env_file:`. Holds.
        case environmentBeatsEnvFile
        /// `env_file:` wins over `environment:`. Wrong.
        case envFileBeatsEnvironment
        /// `expose` opens a port to other containers only. Holds.
        case exposeStaysInternal
        /// `expose` makes a port reachable from the host. Wrong: only `ports:` publishes.
        case exposePublishes
        /// A published port with no address listens on every interface of the host. Holds.
        case publishesOnAllInterfaces
        /// A published port with no address is reachable from the host only. Wrong.
        case publishesOnLocalhostOnly
        /// In `HOST:CONTAINER`, the host port comes first. Holds.
        case hostPortFirst
        /// In a port mapping, the container port comes first. Wrong.
        case containerPortFirst
        /// Inside a container, `localhost` is that container. Holds.
        case localhostIsOwnContainer
        /// Containers reach each other on `localhost`. Wrong: they use the service name.
        case localhostReachesServices
    }

    public enum Line: Sendable, Hashable {
        /// `depends_on` names a service the file does not define: compose refuses the file.
        case undefinedDependency(String)
        /// `condition: service_healthy` on a service with no `healthcheck:`: `up` stops unless the image has one.
        case healthyWithoutHealthcheck(String)
    }

    public let subject: Subject
    /// The sentence the claim was read from, or the compose line it rests on.
    public let sentence: String
    /// What the claim is judged against.
    public let scene: Scene

    public init(subject: Subject, sentence: String, scene: Scene) {
        self.subject = subject
        self.sentence = sentence
        self.scene = scene
    }

    /// Stated in words, as opposed to something the answer's compose file only shows.
    public var isExplicit: Bool {
        switch subject {
        case let .address(address): address.variable == nil
        case .line: false
        case .mapping, .resolves, .statement: true
        }
    }

    /// Identifies the claim across answers, so one stated again is recognised.
    var key: String {
        switch subject {
        case let .address(address):
            "address|\(address.vantage)|\(address.host):\(address.port)|\(address.variable ?? "")"
        case let .mapping(published, target): "mapping|\(published)|\(target)"
        case let .resolves(resolves): "resolves|\(resolves.expression)|\(String(describing: resolves.condition))"
        case let .statement(statement): "statement|\(statement.rawValue)"
        case let .line(line, service): "line|\(line)|\(service)"
        }
    }
}

/// Where an address is used from.
public enum ComposeVantage: Sendable, Hashable {
    /// From the machine running Docker (a browser, `curl` on the host).
    case host
    /// From inside a container of the project; the service, when the answer names it.
    case service(String?)
}

/// What an answer says a substitution gives.
public enum ResolveOutcome: Sendable, Hashable {
    case value(String)
    /// `docker compose` stops with an error.
    case failure
}

/// The variable's state a sentence states for a substitution.
public enum ResolveCondition: Sendable, Hashable {
    case unset(String)
    case empty(String)
    case set(String, String)
}

/// What a conversation shows: its compose file (the last one) and the variables it sets.
public struct Scene: Sendable, Hashable {
    /// `nil` when the conversation shows no compose file.
    public var reading: ComposeProject.Reading?
    public var variables: Variables

    public init(reading: ComposeProject.Reading? = nil, variables: Variables = Variables()) {
        self.reading = reading
        self.variables = variables
    }

    public var project: ComposeProject? {
        if case let .project(project) = reading { return project }
        return nil
    }
}
