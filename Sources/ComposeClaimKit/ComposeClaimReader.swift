/// Finds what an answer says, and what its compose file shows, about how a compose project behaves.
public struct ComposeClaimReader: Sendable {
    /// Also read the answer's compose file for addresses in `environment:` and `depends_on` problems.
    public let checksLines: Bool

    public init(checksLines: Bool = true) {
        self.checksLines = checksLines
    }

    /// The answer's claims. `context` is the question it answers; neither talking about compose means no claims.
    public func claims(in text: String, context: String = "") -> [ComposeClaim] {
        guard Self.isAboutCompose(text) || Self.isAboutCompose(context) else { return [] }
        return allClaims(in: text, earlier: Scene())
    }

    /// Whether the text talks about compose: names it or one of its keys, or shows a compose file.
    public static func isAboutCompose(_ text: String) -> Bool {
        let folded = text.folded
        let markers = ["docker compose", "docker-compose", "compose.yaml", "compose.yml", "compose file",
                       "depends_on", "env_file", "compose project"]
        return markers.contains(where: folded.contains) || AnswerBlocks.split(text).contains { block in
            if case .code = block.kind { return ComposeProject.looksLikeCompose(block.lines) }
            return false
        }
    }

    func allClaims(in text: String, earlier: Scene) -> [ComposeClaim] {
        let blocks = AnswerBlocks.split(text)
        let scene = Self.scene(blocks, text: text, earlier: earlier)
        var claims: [ComposeClaim] = []
        for block in blocks where block.kind == .prose {
            for sentence in Sentences.split(block.lines) {
                claims += StatementReader.statements(in: sentence).map {
                    ComposeClaim(subject: .statement($0), sentence: sentence, scene: scene)
                }
                claims += ResolveReader.claims(sentence, scene: scene)
                claims += MappingReader.claims(sentence, scene: scene)
                claims += AddressReader.claims(sentence, scene: scene)
            }
        }
        if checksLines, !Self.composeBlocks(blocks).isEmpty {
            claims += AddressReader.lines(scene) + Self.dependencyLines(scene)
        }
        return claims
    }

    static func composeBlocks(_ blocks: [AnswerBlock]) -> [AnswerBlock] {
        blocks.filter { block in
            guard case let .code(tag, _) = block.kind, ["yaml", "yml", "compose", "docker-compose", ""].contains(tag)
            else { return false }
            return ComposeProject.looksLikeCompose(block.lines)
        }
    }

    /// The conversation so far plus this answer: its last compose file, its `.env`, its shell exports.
    static func scene(_ blocks: [AnswerBlock], text: String, earlier: Scene) -> Scene {
        var scene = earlier
        var previousProse = ""
        for block in blocks {
            switch block.kind {
            case .prose:
                previousProse = block.lines.joined(separator: " ").folded
            case let .code(tag, info):
                if isDotEnv(tag: tag, info: info, lines: block.lines, previousProse: previousProse) {
                    let parsed = EnvFile.parse(block.lines)
                    scene.variables.dotEnv = parsed.values
                    scene.variables.unread = parsed.unread
                } else if ["bash", "sh", "shell", "zsh", "console", "terminal", ""].contains(tag) {
                    scene.variables.shell.merge(exports(block.lines)) { $1 }
                }
            }
        }
        let compose = composeBlocks(blocks)
        let merged = text.folded.contains("override") || compose.contains { $0.kind != compose[0].kind }
        if compose.count > 1, merged {
            scene.reading = .unreadable("the answer merges several compose files, which this reader does not do")
        } else if let last = compose.last {
            scene.reading = ComposeProject.read(last.lines.joined(separator: "\n"), variables: scene.variables)
        }
        return scene
    }

    /// A ```` ```env ```` or ```` ```dotenv ```` block, one whose info string names `.env`, or a block of bare
    /// assignments right after prose that names `.env`.
    static func isDotEnv(tag: String, info: String, lines: [String], previousProse: String) -> Bool {
        if ["env", "dotenv"].contains(tag) || info.contains(".env") { return true }
        guard ["", "ini", "properties", "text", "bash", "sh", "shell"].contains(tag), previousProse.contains(".env")
        else { return false }
        let content = lines.map(\.trimmed).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return !content.isEmpty && content.allSatisfy { line in
            guard let equals = line.firstIndex(of: "=") else { return false }
            return Names.isName(String(line[..<equals]))
        }
    }

    /// `export NAME=value` and `NAME=value docker compose ...` lines of a shell block.
    static func exports(_ lines: [String]) -> [String: String] {
        var values: [String: String] = [:]
        for raw in lines {
            var line = raw.trimmed
            if line.hasPrefix("$ ") { line = String(line.dropFirst(2)) }
            let words = line.split(separator: " ").map(String.init)
            let assignments: ArraySlice<String>
            if words.first == "export" {
                assignments = words.dropFirst()
            } else if let command = words.firstIndex(where: { !$0.contains("=") }),
                      words[command...].starts(with: ["docker", "compose"]) || words[command] == "docker-compose" {
                assignments = words[..<command]
            } else {
                continue
            }
            for assignment in assignments {
                guard let equals = assignment.firstIndex(of: "="), Names.isName(String(assignment[..<equals]))
                else { continue }
                let value = String(assignment[assignment.index(after: equals)...])
                values[String(assignment[..<equals])] = value.trimmingCharacters(in: .init(charactersIn: "\"'"))
            }
        }
        return values
    }

    static func dependencyLines(_ scene: Scene) -> [ComposeClaim] {
        guard let project = scene.project else { return [] }
        var claims: [ComposeClaim] = []
        for service in project.services {
            for dependency in service.dependsOn {
                let sentence = "\(service.name): depends_on \(dependency.name) (\(dependency.condition))"
                guard let target = project.services.first(where: { $0.name == dependency.name }) else {
                    let line = ComposeClaim.Line.undefinedDependency(dependency.name)
                    claims.append(ComposeClaim(subject: .line(line, service: service.name), sentence: sentence,
                                               scene: scene))
                    continue
                }
                if dependency.condition == "service_healthy", !target.hasHealthcheck {
                    claims.append(ComposeClaim(subject: .line(.healthyWithoutHealthcheck(target.name),
                                                              service: service.name), sentence: sentence, scene: scene))
                }
            }
        }
        return claims
    }

    /// Carries what this answer shows into the conversation, for the next answer.
    static func remember(_ text: String, into scene: inout Scene) {
        scene = Self.scene(AnswerBlocks.split(text), text: text, earlier: scene)
    }
}
