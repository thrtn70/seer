import Testing
import CoreGraphics
import SeerModel
import SeerInference
import SeerPersonalization
@testable import SeerCoordinator

private final class ParamsEngine: InferenceEngine, @unchecked Sendable {
    let kind: EngineKind = .llamaCpp
    var isAvailable: Bool { true }
    private(set) var lastParams: SamplingParams?
    func warmUp() async {}
    func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error> {
        lastParams = params
        return AsyncThrowingStream { cont in cont.yield(" hi"); cont.finish() }
    }
}
@MainActor
private func autoCtx(_ bundle: String = "app.a") -> CaptureContext {
    CaptureContext(bundleID: bundle, focusedRole: "AXTextArea", focusedSubrole: nil,
                   textBeforeCaret: "Thanks for", textAfterCaret: "", selectionLength: 0,
                   caretRect: CGRect(x: 10, y: 10, width: 2, height: 18),
                   prefixHash: 9, capturedAt: ContinuousClock().now)
}
private func toneSnapshot(brevity: Double, version: UInt64 = 1) -> ProfileSnapshot {
    ProfileSnapshot(version: version, totalSamples: 40,
                    global: ToneScores(formality: 0.5, warmth: 0.5, brevity: brevity), apps: [:],
                    overrides: .neutral)
}

@Suite struct CoordinatorAutoTempTests {
    @Test @MainActor func autoOnDerivesTemperatureFromBrevity() async {
        let cache = ProfileCache()
        cache.publish(toneSnapshot(brevity: 1.0))          // → 0.25
        let e = ParamsEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { autoCtx() },
                                      profileCache: cache)
        c.setAutoTemperature(true)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.lastParams == SamplingParams(temperature: 0.25, topK: 40, topP: 0.9, maxTokens: 24))
    }
    @Test @MainActor func autoOffUsesTheManualSliderEvenWithTone() async {
        let cache = ProfileCache()
        cache.publish(toneSnapshot(brevity: 1.0))
        let e = ParamsEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { autoCtx() },
                                      profileCache: cache)
        c.setSamplingParams(SamplingParams(temperature: 0.4, maxTokens: 24))
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.lastParams?.temperature == 0.4)
    }
    @Test @MainActor func autoOnWithoutToneFallsBackToManual() async {
        // Below-threshold snapshot ⇒ tone(for:) nil ⇒ pinned brevity nil ⇒ manual value.
        let cache = ProfileCache()
        cache.publish(ProfileSnapshot(version: 1, totalSamples: 3, global: nil, apps: [:],
                                      overrides: .neutral))
        let e = ParamsEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { autoCtx() },
                                      profileCache: cache)
        c.setAutoTemperature(true)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.lastParams?.temperature == 0.2)
    }
    @Test @MainActor func autoUsesPinnedBrevityUntilFocusChanges() async {
        // Displayed-vs-effective divergence is by design: effective uses the PIN.
        let cache = ProfileCache()
        cache.publish(toneSnapshot(brevity: 1.0, version: 1))     // pin → 0.25
        let e = ParamsEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { autoCtx() },
                                      profileCache: cache)
        c.setAutoTemperature(true)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        cache.publish(toneSnapshot(brevity: 0.0, version: 2))     // live now says 0.45
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.lastParams?.temperature == 0.25)                // still the pin
        c._test_invalidateFocus()
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        // Tolerance, not ==: 0.25 + 0.20·1 accumulates ULP error against the 0.45 literal.
        #expect(abs((e.lastParams?.temperature ?? 0) - 0.45) < 1e-9)   // re-pinned from v2
    }
    @Test @MainActor func toggleAppliesFromTheNextRequest() async {
        let cache = ProfileCache()
        cache.publish(toneSnapshot(brevity: 1.0))
        let e = ParamsEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { autoCtx() },
                                      profileCache: cache)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.lastParams?.temperature == 0.2)
        c.setAutoTemperature(true)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.lastParams?.temperature == 0.25)
    }
    @Test @MainActor func displayHintTracksTheLiveGlobalTone() {
        let cache = ProfileCache()
        let c = SuggestionCoordinator(engine: ParamsEngine(), inserter: nil,
                                      capture: { nil }, profileCache: cache)
        #expect(c.autoTemperatureDisplayHint == nil)
        cache.publish(toneSnapshot(brevity: 0.0))
        #expect(abs((c.autoTemperatureDisplayHint ?? 0) - 0.45) < 1e-9)
    }
    @Test @MainActor func displayHintReflectsPinnedBrevity() {
        // RED against a hint still reading `global`: pins live in the snapshot and the hint
        // must read the EFFECTIVE global tone.
        let cache = ProfileCache()
        let c = SuggestionCoordinator(engine: ParamsEngine(), inserter: nil,
                                      capture: { nil }, profileCache: cache)
        cache.publish(ProfileSnapshot(version: 1, totalSamples: 40,
                                      global: ToneScores(formality: 0.5, warmth: 0.5, brevity: 0.0),
                                      apps: [:],
                                      overrides: ToneOverrides(formality: nil, warmth: nil, brevity: 1.0)))
        #expect(c.autoTemperatureDisplayHint == 0.25)      // pinned brevity 1.0 → 0.25, not 0.45
    }
    @Test @MainActor func applyTuningWiresAutoTemperature() async {
        // The compile-error sweep can't catch apply() ignoring the field — this test does.
        let cache = ProfileCache()
        cache.publish(toneSnapshot(brevity: 1.0))
        let e = ParamsEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { autoCtx() },
                                      profileCache: cache)
        c.apply(CoordinatorTuning(enabled: true, pausedBundles: [],
                                  sampling: SamplingParams(temperature: 0.2, maxTokens: 24),
                                  autoTemperature: true, fontName: nil, fontSize: 13))
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.lastParams?.temperature == 0.25)
    }
}
