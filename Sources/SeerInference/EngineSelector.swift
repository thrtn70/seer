import SeerModel

public final class EngineSelector: Sendable {
    private let engines: [any InferenceEngine]
    public init(engines: [any InferenceEngine]) { self.engines = engines }

    /// First available engine (hot-path engine when ordered llama.cpp-first).
    public var primary: (any InferenceEngine)? { engines.first { $0.isAvailable } }

    /// Streams from the primary engine; on a typed guardrail/contextOverflow error,
    /// retries the same request on the next available engine.
    public func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error> {
        let candidates = engines.filter { $0.isAvailable }
        return AsyncThrowingStream { cont in
            let task = Task {
                for (idx, engine) in candidates.enumerated() {
                    do {
                        for try await tok in engine.stream(prompt: prompt, params: params, cacheKey: cacheKey) {
                            try Task.checkCancellation()
                            cont.yield(tok)
                        }
                        cont.finish()
                        return
                    } catch let e as EngineError where (e == .guardrail || e == .contextOverflow)
                                                       && idx < candidates.count - 1 {
                        continue   // fall through to the next engine
                    } catch {
                        cont.finish(throwing: error); return
                    }
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
