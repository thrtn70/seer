import Testing
import CoreGraphics
import SeerModel
import SeerInference
import AppKit
@testable import SeerOverlay
@testable import SeerCoordinator

private final class ParamsCapturingEngine: InferenceEngine, @unchecked Sendable {
    let kind: EngineKind = .llamaCpp
    var isAvailable: Bool { true }
    /// Mutated from `stream` without synchronisation: the coordinator calls it from a `Task {}`
    /// that inherits MainActor isolation, and the `@Test @MainActor` bodies read it on MainActor —
    /// so it is MainActor-confined in practice. Worth stating, since `@unchecked Sendable` opts
    /// this type out of the compiler's check.
    private(set) var lastParams: SamplingParams?
    func warmUp() async {}
    func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error> {
        lastParams = params
        return AsyncThrowingStream { cont in cont.yield(" hello"); cont.finish() }
    }
}

@MainActor
private func ctx(_ before: String) -> CaptureContext {
    CaptureContext(bundleID: "com.apple.TextEdit", focusedRole: "AXTextArea", focusedSubrole: nil,
                   textBeforeCaret: before, textAfterCaret: "", selectionLength: 0,
                   caretRect: CGRect(x: 10, y: 10, width: 2, height: 18),
                   prefixHash: 99, capturedAt: ContinuousClock().now)
}

@Suite struct CoordinatorSettingsTests {
    @Test @MainActor func defaultSamplingParamsMatchShippedBehavior() async {
        // Pins temperature 0.2 (NOT SamplingParams()'s 0.3 default), topK 40, topP 0.9, max 24.
        let e = ParamsCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { ctx("Thanks for") })
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.lastParams == SamplingParams(temperature: 0.2, topK: 40, topP: 0.9, maxTokens: 24))
    }
    @Test @MainActor func setSamplingParamsAppliesToNextRequest() async {
        let e = ParamsCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { ctx("Thanks for") })
        c.setSamplingParams(SamplingParams(temperature: 0.5, maxTokens: 8))
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.lastParams == SamplingParams(temperature: 0.5, maxTokens: 8))
    }
    @Test @MainActor func setOverlayFontDismissesAndDropsInlineRenderer() {
        let c = SuggestionCoordinator(engine: ParamsCapturingEngine(), inserter: nil, capture: { nil })
        c._test_setShowing(Suggestion(text: " hi", chunks: [" hi"], forPrefixHash: 1),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        #expect(c.testInlineRenderer != nil)
        c.setOverlayFont(name: "Menlo", size: 15)
        #expect(c.testState == .idle)
        #expect(c.testCurrent == nil)
        #expect(c.testInlineRenderer == nil)
        #expect(c.testResolvedFont == ResolvedFont(name: "Menlo", size: 15))
    }
    /// The pill drop needs its own coordinator: `renderer(for:)` only builds a PillRenderer when
    /// `pillRenderer == nil`, so a survivor would keep its old font forever — breaking the font
    /// setting exactly in the `knownBad` pill-fallback apps (Slack, VSCode).
    @Test @MainActor func setOverlayFontDropsPillRenderer() {
        let c = SuggestionCoordinator(engine: ParamsCapturingEngine(), inserter: nil, capture: { nil })
        c._test_setShowing(Suggestion(text: " hi", chunks: [" hi"], forPrefixHash: 1),
                           mode: .pill(CGPoint(x: 50, y: 50)))
        #expect(c.testPillExists)
        c.setOverlayFont(name: "Menlo", size: 15)
        #expect(!c.testPillExists)
    }
    @Test @MainActor func setOverlayFontSanitizesThroughResolve() {
        let c = SuggestionCoordinator(engine: ParamsCapturingEngine(), inserter: nil, capture: { nil })
        c.setOverlayFont(name: "   ", size: 500)
        #expect(c.testResolvedFont == ResolvedFont(name: nil, size: 13))
    }
    /// Pins the dismiss-before-drop ordering in `setOverlayFont`. Nilling the renderers before
    /// `dismiss()` runs would leave `inline?.clear()` to no-op on nil, deallocating an
    /// still-ordered-in NSPanel — the crash this ordering exists to prevent. Renderer-existence
    /// assertions can't see that reorder; the panel's visibility can.
    @Test @MainActor func setOverlayFontClearsRendererBeforeDroppingIt() throws {
        let c = SuggestionCoordinator(engine: ParamsCapturingEngine(), inserter: nil, capture: { nil })
        c._test_setShowing(Suggestion(text: " hi", chunks: [" hi"], forPrefixHash: 1),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        // Strong local ref: the coordinator drops its own below, and the assertion needs the
        // renderer (and its panel) to outlive that.
        let renderer = try #require(c.testInlineRenderer)
        // _test_setShowing only *creates* the renderer — drive it to actually order the panel in.
        renderer.setPlacement(.inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        renderer.update(text: " hi")
        #expect(renderer.ghostPanel.panel.isVisible)    // precondition: the panel is really on screen
        c.setOverlayFont(name: "Menlo", size: 15)
        #expect(c.testInlineRenderer == nil)            // coordinator dropped its reference...
        #expect(!renderer.ghostPanel.panel.isVisible)   // ...but clear() reached the panel FIRST
    }
    @Test @MainActor func nextRendererUsesNewFont() throws {
        let c = SuggestionCoordinator(engine: ParamsCapturingEngine(), inserter: nil, capture: { nil })
        c.setOverlayFont(name: "Menlo", size: 15)
        c._test_setShowing(Suggestion(text: " hi", chunks: [" hi"], forPrefixHash: 1),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        // InlineRenderer's content view *is* its ghost-text label: assert the new font actually
        // reached the NSTextField, not merely that `resolvedFont` changed.
        let renderer = try #require(c.testInlineRenderer)
        let label = try #require(renderer.ghostPanel.panel.contentView as? NSTextField)
        // AppKit resolves the requested "Menlo" to the concrete face "Menlo-Regular";
        // familyName is what round-trips.
        #expect(label.font?.familyName == "Menlo")
        #expect(label.font?.pointSize == 15)
    }

    // MARK: apply(_:) — startup replay
    @Test @MainActor func applyWiresEnabledPausedAndFont() {
        // Covers 4 of the 5 tuning fields; sampling needs a request to observe, below.
        let c = SuggestionCoordinator(engine: ParamsCapturingEngine(), inserter: nil, capture: { nil })
        c.apply(CoordinatorTuning(enabled: false,
                                  pausedBundles: ["com.apple.TextEdit", "com.foo.bar"],
                                  sampling: SamplingParams(temperature: 0.5, maxTokens: 8),
                                  autoTemperature: false,
                                  fontName: "Menlo", fontSize: 15))
        #expect(c.isEnabled == false)
        #expect(c.pausedBundles == ["com.apple.TextEdit", "com.foo.bar"])
        #expect(c.testResolvedFont == ResolvedFont(name: "Menlo", size: 15))
    }
    @Test @MainActor func applySamplingReachesTheEngine() async {
        // The 5th field, asserted where it actually lands: the engine's params, not a seam.
        let e = ParamsCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { ctx("Thanks for") })
        c.apply(CoordinatorTuning(enabled: true, pausedBundles: [],
                                  sampling: SamplingParams(temperature: 0.5, maxTokens: 8),
                                  autoTemperature: false,
                                  fontName: nil, fontSize: 13))
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.lastParams == SamplingParams(temperature: 0.5, topK: 40, topP: 0.9, maxTokens: 8))
    }
    @Test @MainActor func applyOfDefaultTuningLeavesShippedBehavior() async {
        // Replaying a fresh install's settings must be a no-op against the shipped defaults —
        // i.e. apply() itself introduces no drift on the overwhelmingly common launch path.
        let e = ParamsCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { ctx("Thanks for") })
        c.apply(CoordinatorTuning(enabled: true, pausedBundles: [],
                                  sampling: SamplingParams(temperature: 0.2, maxTokens: 24),
                                  autoTemperature: false,
                                  fontName: nil, fontSize: 13))
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(c.isEnabled)
        #expect(c.pausedBundles.isEmpty)
        #expect(e.lastParams == SamplingParams(temperature: 0.2, topK: 40, topP: 0.9, maxTokens: 24))
        #expect(c.testResolvedFont == OverlayFont.resolve(FontDescriptorInput(name: nil, size: nil)))
    }
}
