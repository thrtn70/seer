/// A streamed suggestion plus its word chunks (for next-word accept) and the prefix hash it
/// was generated for (to drop stale streams when context moves on).
public struct Suggestion: Sendable, Equatable {
    public let text: String
    public let chunks: [String]
    public let forPrefixHash: UInt64
    public init(text: String, chunks: [String], forPrefixHash: UInt64) {
        self.text = text; self.chunks = chunks; self.forPrefixHash = forPrefixHash
    }
}
