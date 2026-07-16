import Testing
import SeerModel
@testable import SeerInference

private final class MockEngine: InferenceEngine, Sendable {
    let kind: EngineKind
    let available: Bool
    let tokens: [String]
    let throwError: EngineError?
    init(_ kind: EngineKind, available: Bool, tokens: [String] = [], error: EngineError? = nil) {
        self.kind = kind; self.available = available; self.tokens = tokens; self.throwError = error
    }
    var isAvailable: Bool { available }
    func warmUp() async {}
    func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            if let e = throwError { cont.finish(throwing: e); return }
            for t in tokens { cont.yield(t) }
            cont.finish()
        }
    }
}

@Suite struct EngineSelectorTests {
    @Test func picksFirstAvailable() {
        let sel = EngineSelector(engines: [
            MockEngine(.foundationModels, available: false),
            MockEngine(.llamaCpp, available: true),
        ])
        #expect(sel.primary?.kind == .llamaCpp)
    }
    @Test func fallsBackOnGuardrail() async throws {
        let sel = EngineSelector(engines: [
            MockEngine(.foundationModels, available: true, error: .guardrail),
            MockEngine(.llamaCpp, available: true, tokens: [" ok"]),
        ])
        var out = ""
        for try await tok in sel.stream(prompt: PromptPayload(stablePrefix: "", context: "hi"),
                                        params: .init(), cacheKey: nil) {
            out += tok
        }
        #expect(out == " ok")
    }

    @Test func noAvailableEnginesFinishesEmpty() async throws {
        let sel = EngineSelector(engines: [
            MockEngine(.foundationModels, available: false),
            MockEngine(.llamaCpp, available: false),
        ])
        var tokens: [String] = []
        for try await tok in sel.stream(prompt: PromptPayload(stablePrefix: "", context: "hi"),
                                        params: .init(), cacheKey: nil) {
            tokens.append(tok)
        }
        #expect(tokens.isEmpty)
    }

    @Test func lastEngineGuardrailPropagates() async throws {
        let sel = EngineSelector(engines: [
            MockEngine(.foundationModels, available: true, error: .guardrail),
            MockEngine(.llamaCpp, available: true, error: .guardrail),
        ])
        var caught: EngineError?
        do {
            for try await _ in sel.stream(prompt: PromptPayload(stablePrefix: "", context: "hi"),
                                          params: .init(), cacheKey: nil) {}
        } catch let e as EngineError {
            caught = e
        }
        #expect(caught == .guardrail)
    }

    @Test func nonFallbackErrorPropagatesImmediately() async throws {
        let sel = EngineSelector(engines: [
            MockEngine(.foundationModels, available: true, error: .backend("boom")),
            MockEngine(.llamaCpp, available: true, tokens: [" unused"]),
        ])
        var tokens: [String] = []
        var caught: EngineError?
        do {
            for try await tok in sel.stream(prompt: PromptPayload(stablePrefix: "", context: "hi"),
                                            params: .init(), cacheKey: nil) {
                tokens.append(tok)
            }
        } catch let e as EngineError {
            caught = e
        }
        #expect(caught == .backend("boom"))
        #expect(!tokens.contains(" unused"))
    }

    @Test func fallsBackOnContextOverflow() async throws {
        let sel = EngineSelector(engines: [
            MockEngine(.foundationModels, available: true, error: .contextOverflow),
            MockEngine(.llamaCpp, available: true, tokens: [" ok"]),
        ])
        var out = ""
        for try await tok in sel.stream(prompt: PromptPayload(stablePrefix: "", context: "hi"),
                                        params: .init(), cacheKey: nil) {
            out += tok
        }
        #expect(out == " ok")
    }
}
