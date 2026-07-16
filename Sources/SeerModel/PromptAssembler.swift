/// Builds a Qwen2.5 ChatML autocomplete prompt (assistant-prefill continuation) so the
/// instruct model is on-distribution. The system+user scaffold is byte-stable (the KV-cache
/// anchor); the text-before-caret is the volatile context the model continues in the
/// assistant turn. Stop generation at `<|im_end|>` (handled by the engine).
public struct PromptAssembler: Sendable {
    public static let defaultSystem =
        "You are an inline autocomplete engine inside a text field. Continue the user's text "
        + "with a short, natural continuation of a few words. Output only the continuation — "
        + "no preamble, no quotation marks, and do not repeat the text so far."
    public static let defaultUser =
        "Continue my text, picking up exactly where it leaves off."

    public let system: String
    public let user: String
    public init(system: String = PromptAssembler.defaultSystem,
                user: String = PromptAssembler.defaultUser) {
        self.system = system; self.user = user
    }

    /// Byte-stable ChatML scaffold up to the open assistant turn.
    public var scaffold: String {
        "<|im_start|>system\n\(system)<|im_end|>\n"
        + "<|im_start|>user\n\(user)<|im_end|>\n"
        + "<|im_start|>assistant\n"
    }

    /// Assemble a ChatML PromptPayload: scaffold as the stable prefix, text-before-caret as
    /// the volatile context (placed at the start of the assistant turn for the model to continue).
    public func assemble(textBeforeCaret: String) -> PromptPayload {
        PromptPayload(stablePrefix: scaffold, context: textBeforeCaret, parseSpecial: true)
    }
}
