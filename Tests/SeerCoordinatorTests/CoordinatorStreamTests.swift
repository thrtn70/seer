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
        try? await Task.sleep(for: .milliseconds(80))   // let the inflight stream task drain
        #expect(c.testState == .showing)
        #expect(c.testCurrent?.text == " issued a refund")
        #expect(c.testCurrent?.chunks == [" issued ", "a ", "refund"])
    }
    @Test @MainActor func shortContextDismisses() async {
        let c = SuggestionCoordinator(engine: ScriptedEngine([" x"]), inserter: nil, capture: { ctx("1") })
        await c._test_requestSuggestion()
        #expect(c.testState == .idle)
    }
}
