public struct PromptPayload: Sendable, Equatable {
    /// Byte-stable prefix (system style descriptor + examples) — the KV-cache reuse anchor.
    public let stablePrefix: String
    /// Volatile context (text before/after the caret) appended after the prefix.
    public let context: String
    /// When true, the engine tokenizes with `parse_special` so ChatML control tokens
    /// (`<|im_start|>`/`<|im_end|>`) become single special tokens, not literal text.
    public let parseSpecial: Bool
    public init(stablePrefix: String, context: String, parseSpecial: Bool = false) {
        self.stablePrefix = stablePrefix; self.context = context; self.parseSpecial = parseSpecial
    }
    public var fullText: String { stablePrefix + context }
}
