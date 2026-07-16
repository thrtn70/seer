import SeerModel

public enum EngineError: Error, Equatable, Sendable {
    case guardrail            // FM content-safety refusal
    case contextOverflow      // prompt exceeded context window
    case unavailable
    case backend(String)      // wrapped backend failure
}

public protocol InferenceEngine: Sendable {
    var kind: EngineKind { get }
    var isAvailable: Bool { get }
    func warmUp() async
    /// Streams completion tokens. Honors Task cancellation (break the loop ⇒ stop).
    func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error>
}
