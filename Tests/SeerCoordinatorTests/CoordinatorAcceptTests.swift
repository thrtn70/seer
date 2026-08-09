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

/// The re-anchor runs via DispatchQueue.main.asyncAfter, so there is no task handle to
/// await; poll with a deadline instead of a fixed sleep (flaky under load).
@MainActor
private func pollUntil(deadline: Duration = .seconds(2),
                       _ condition: @MainActor () -> Bool) async {
    let clock = ContinuousClock()
    let end = clock.now.advanced(by: deadline)
    while !condition() && clock.now < end {
        try? await Task.sleep(for: .milliseconds(1))
    }
}

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
        await pollUntil { c.testState == .showing }    // let the (0-delay) re-anchor run
        #expect(c.testState == .showing)
        #expect(c.testCurrent?.chunks == ["a ", "refund"])
    }
    @Test @MainActor func nextWordAcceptFiresOnAcceptWithOneWord() {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(),
                                      capture: { reanchorCtx() }, reanchorDelay: 0.0)
        var counts: [Int] = []
        c.onAccept = { counts.append($0) }
        c._test_setShowing(Suggestion(text: "issued a refund", chunks: ["issued ", "a ", "refund"], forPrefixHash: 7),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        _ = c.handleKey(code: kTab, hasShift: false)  // Tab = next word
        #expect(counts == [1])
    }
    @Test @MainActor func wholeLineAcceptFiresFullWordCount() {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(), capture: { reanchorCtx() })
        var counts: [Int] = []
        c.onAccept = { counts.append($0) }
        c._test_setShowing(Suggestion(text: "issued a refund", chunks: ["issued ", "a ", "refund"], forPrefixHash: 7),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        _ = c.handleKey(code: kTab, hasShift: true)   // ⇧Tab = whole line
        #expect(counts == [3])
    }
    @Test @MainActor func noAcceptEventWhenIdle() {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(), capture: { reanchorCtx() })
        var counts: [Int] = []
        c.onAccept = { counts.append($0) }
        _ = c.handleKey(code: kTab, hasShift: false)  // nothing showing
        #expect(counts.isEmpty)
    }
    @Test @MainActor func sequentialAcceptsFireOncePerAccept() async {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(),
                                      capture: { reanchorCtx() }, reanchorDelay: 0.0)
        var counts: [Int] = []
        c.onAccept = { counts.append($0) }
        c._test_setShowing(Suggestion(text: "issued a refund", chunks: ["issued ", "a ", "refund"], forPrefixHash: 7),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        _ = c.handleKey(code: kTab, hasShift: false)
        await pollUntil { c.testState == .showing }    // let the (0-delay) re-anchor restore .showing
        _ = c.handleKey(code: kTab, hasShift: false)
        #expect(counts == [1, 1])
    }
    @Test @MainActor func dismissPathsDoNotFireOnAccept() {
        let kEsc: Int64 = 53      // KeyCodes.escape → .dismiss while showing
        let kLetterA: Int64 = 0   // 'a' → .typeOverDismiss while showing
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(), capture: { reanchorCtx() })
        var counts: [Int] = []
        c.onAccept = { counts.append($0) }
        c._test_setShowing(Suggestion(text: "issued a refund", chunks: ["issued ", "a ", "refund"], forPrefixHash: 7),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        _ = c.handleKey(code: kEsc, hasShift: false)      // Esc: dismiss
        c._test_setShowing(Suggestion(text: "issued a refund", chunks: ["issued ", "a ", "refund"], forPrefixHash: 7),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        _ = c.handleKey(code: kLetterA, hasShift: false)  // letter: typeOverDismiss
        #expect(counts.isEmpty)
    }
}
