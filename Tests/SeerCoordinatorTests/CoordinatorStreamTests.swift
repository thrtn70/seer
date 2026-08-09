import Testing
import CoreGraphics
import SeerModel
import SeerInference
@testable import SeerCoordinator

private final class ScriptedEngine: InferenceEngine, @unchecked Sendable {
    let kind: EngineKind = .llamaCpp
    var isAvailable: Bool { true }
    let pieces: [String]
    init(_ pieces: [String]) { self.pieces = pieces }
    func warmUp() async {}
    func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error> {
        let pieces = self.pieces
        return AsyncThrowingStream { cont in for p in pieces { cont.yield(p) }; cont.finish() }
    }
}

@MainActor
private func ctx(_ before: String) -> CaptureContext {
    CaptureContext(bundleID: "com.apple.TextEdit", focusedRole: "AXTextArea", focusedSubrole: nil,
                   textBeforeCaret: before, textAfterCaret: "", selectionLength: 0,
                   caretRect: CGRect(x: 10, y: 10, width: 2, height: 18),
                   prefixHash: 99, capturedAt: ContinuousClock().now)
}

@Suite struct CoordinatorStreamTests {
    @Test @MainActor func streamPopulatesShowingSuggestion() async {
        let c = SuggestionCoordinator(engine: ScriptedEngine([" issued", " a", " refund"]),
                                      inserter: nil, capture: { ctx("Thanks for") })
        await c._test_requestSuggestion()
        await c._test_awaitInflight()                   // deterministic drain (no sleep)
        #expect(c.testState == .showing)
        #expect(c.testCurrent?.text == " issued a refund")
        #expect(c.testCurrent?.chunks == [" issued ", "a ", "refund"])
    }
    @Test @MainActor func shortContextDismisses() async {
        let c = SuggestionCoordinator(engine: ScriptedEngine([" x"]), inserter: nil, capture: { ctx("1") })
        await c._test_requestSuggestion()
        #expect(c.testState == .idle)
    }
    @Test @MainActor func latencyFiresExactlyOncePerRenderedSuggestion() async {
        let c = SuggestionCoordinator(engine: ScriptedEngine([" issued", " a", " refund"]),
                                      inserter: nil, capture: { ctx("Thanks for") })
        var samples: [Double] = []
        c.onSuggestionLatency = { samples.append($0) }
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(samples.count == 1)
        #expect(samples.allSatisfy { $0 >= 0 })
    }
    @Test @MainActor func latencyNotFiredWhenGateDismisses() async {
        let c = SuggestionCoordinator(engine: ScriptedEngine([" x"]), inserter: nil, capture: { ctx("1") })
        var samples: [Double] = []
        c.onSuggestionLatency = { samples.append($0) }
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(samples.isEmpty)
    }
    @Test @MainActor func latencyNotFiredWhenOutputNeverDisplayable() async {
        // Digits only: GhostText.displayable requires a letter, so .showing never happens.
        let c = SuggestionCoordinator(engine: ScriptedEngine(["12", "34"]),
                                      inserter: nil, capture: { ctx("Thanks for") })
        var samples: [Double] = []
        c.onSuggestionLatency = { samples.append($0) }
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(samples.isEmpty)
    }
    @Test @MainActor func latencyNotFiredOnEmptyStream() async {
        let c = SuggestionCoordinator(engine: ScriptedEngine([]),
                                      inserter: nil, capture: { ctx("Thanks for") })
        var samples: [Double] = []
        c.onSuggestionLatency = { samples.append($0) }
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(samples.isEmpty)
    }
    @Test @MainActor func latencyFiresAtFirstDisplayablePieceNotLast() async {
        // First piece is punctuation (not displayable); the second makes it displayable.
        let c = SuggestionCoordinator(engine: ScriptedEngine(["...", " hello", " world"]),
                                      inserter: nil, capture: { ctx("Thanks for") })
        var samples: [Double] = []
        var textAtFire: String?
        c.onSuggestionLatency = { [weak c] ms in
            samples.append(ms)
            textAtFire = c?.testCurrent?.text
        }
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(samples.count == 1)
        #expect(textAtFire == "... hello")
    }
    @Test @MainActor func latencyFiresOncePerRequestAcrossSequentialRequests() async {
        let c = SuggestionCoordinator(engine: ScriptedEngine([" issued", " a", " refund"]),
                                      inserter: nil, capture: { ctx("Thanks for") })
        var samples: [Double] = []
        c.onSuggestionLatency = { samples.append($0) }
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(samples.count == 2)
    }
}
