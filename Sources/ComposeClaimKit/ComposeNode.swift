/// A YAML value as far as a compose file needs one. Scalars stay text, the way compose reads most of them.
public indirect enum ComposeNode: Sendable, Hashable {
    case null
    case scalar(String)
    case list([ComposeNode])
    case map([ComposeEntry])

    /// The value under a key of a mapping; the last one when a key repeats.
    public subscript(key: String) -> ComposeNode? {
        entries?.last { $0.key == key }?.value
    }

    public var text: String? {
        if case let .scalar(text) = self { return text }
        return nil
    }

    public var items: [ComposeNode]? {
        if case let .list(items) = self { return items }
        return nil
    }

    public var entries: [ComposeEntry]? {
        if case let .map(entries) = self { return entries }
        return nil
    }
}

public struct ComposeEntry: Sendable, Hashable {
    public let key: String
    public let value: ComposeNode

    public init(key: String, value: ComposeNode) {
        self.key = key
        self.value = value
    }
}
