import Testing
import CoreGraphics
import SeerModel
import SeerInference
@testable import SeerCoordinator

private final class NoEngine: InferenceEngine, @unchecked Sendable {
    let kind: EngineKind = .llamaCpp
    var isAvailable: Bool { true }
    func warmUp() async {}
    func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
}

@MainActor private func ctx(_ bundle: String) -> CaptureContext {
    CaptureContext(bundleID: bundle, focusedRole: "AXTextArea", focusedSubrole: nil,
                   textBeforeCaret: "Thanks for", textAfterCaret: "", selectionLength: 0,
                   caretRect: CGRect(x: 10, y: 10, width: 2, height: 18),
                   prefixHash: 1, capturedAt: ContinuousClock().now)
}

@Suite struct CoordinatorPolicyTests {
    @Test @MainActor func disabledDoesNotSuggest() async {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: nil, capture: { ctx("com.apple.TextEdit") })
        var notified = 0
        c.onStateChanged = { notified += 1 }
        c.setEnabled(false)
        #expect(notified == 1)
        await c._test_requestSuggestion()
        #expect(c.testState == .idle)
        #expect(c.testCurrent == nil)
    }
    @Test @MainActor func pausedBundleDoesNotSuggest() async {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: nil, capture: { ctx("com.apple.TextEdit") })
        c.setPaused(true, bundleID: "com.apple.TextEdit")
        #expect(c.isPaused(bundleID: "com.apple.TextEdit") == true)
        await c._test_requestSuggestion()
        #expect(c.testState == .idle)
    }
    @Test @MainActor func panicTogglesEnabledAndNotifies() {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: nil, capture: { nil })
        var notified = 0
        c.onStateChanged = { notified += 1 }
        #expect(c.isEnabled == true)
        c.panic()
        #expect(c.isEnabled == false)
        #expect(notified == 1)
        c.panic()
        #expect(c.isEnabled == true)
        #expect(notified == 2)
    }
}
