import Testing
import CoreGraphics
import SeerModel
import SeerInference
import SeerInsertion
@testable import SeerCoordinator

private final class NoEngine: InferenceEngine, @unchecked Sendable {
    let kind: EngineKind = .llamaCpp
    var isAvailable: Bool { true }
    func warmUp() async {}
    func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
}
@MainActor private final class Spy: TextInserting {
    var ins: [String] = []
    func insert(_ t: String, gate: KeystrokeGate) { ins.append(t) }
}
@MainActor private func reanchorCtx() -> CaptureContext {
    CaptureContext(bundleID: "com.apple.TextEdit", focusedRole: "AXTextArea", focusedSubrole: nil,
                   textBeforeCaret: "Thanks issued ", textAfterCaret: "", selectionLength: 0,
                   caretRect: CGRect(x: 40, y: 10, width: 2, height: 18),
                   prefixHash: 7, capturedAt: ContinuousClock().now)
}
private let kTab: Int64 = 48

@Suite struct CoordinatorAcceptTests {
    @Test @MainActor func wholeLineInsertsJoinedAndGoesIdle() {
        let spy = Spy()
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: spy, capture: { reanchorCtx() })
        c._test_setShowing(Suggestion(text: "issued a refund", chunks: ["issued ", "a ", "refund"], forPrefixHash: 7),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        _ = c.handleKey(code: kTab, hasShift: true)   // ⇧Tab
        #expect(spy.ins == ["issued a refund"])
        #expect(c.testState == .idle)
        #expect(c.testCurrent == nil)
    }
    @Test @MainActor func nextWordInsertsFirstChunkAndKeepsRemaining() async {
        let spy = Spy()
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: spy,
                                      capture: { reanchorCtx() }, reanchorDelay: 0.0)
        c._test_setShowing(Suggestion(text: "issued a refund", chunks: ["issued ", "a ", "refund"], forPrefixHash: 7),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        _ = c.handleKey(code: kTab, hasShift: false)  // Tab
        #expect(spy.ins == ["issued "])
        try? await Task.sleep(for: .milliseconds(30))  // let the (0-delay) re-anchor run
        #expect(c.testState == .showing)
        #expect(c.testCurrent?.chunks == ["a ", "refund"])
    }
}
