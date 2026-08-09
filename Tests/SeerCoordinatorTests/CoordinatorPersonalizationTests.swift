import Testing
import CoreGraphics
import SeerModel
import SeerInference
import SeerPersonalization
@testable import SeerCoordinator

/// Captures every prompt the coordinator sends — byte-level assertions on the ChatML text.
private final class PromptCapturingEngine: InferenceEngine, @unchecked Sendable {
    let kind: EngineKind = .llamaCpp
    var isAvailable: Bool { true }
    /// MainActor-confined in practice (same rationale as ParamsCapturingEngine).
    private(set) var prompts: [PromptPayload] = []
    func warmUp() async {}
    func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error> {
        prompts.append(prompt)
        return AsyncThrowingStream { cont in cont.yield(" hi"); cont.finish() }
    }
}

@MainActor
private func ctxFor(_ bundle: String, _ before: String) -> CaptureContext {
    CaptureContext(bundleID: bundle, focusedRole: "AXTextArea", focusedSubrole: nil,
                   textBeforeCaret: before, textAfterCaret: "", selectionLength: 0,
                   caretRect: CGRect(x: 10, y: 10, width: 2, height: 18),
                   prefixHash: 99, capturedAt: ContinuousClock().now)
}

/// Active snapshot: global tone + a distinct per-app override for "app.a" (with phrases),
/// so app.a and any-other-app render different descriptor bytes.
private func activeSnapshot(version: UInt64 = 1) -> ProfileSnapshot {
    ProfileSnapshot(version: version, totalSamples: 60,
                    global: ToneScores(formality: 0.5, warmth: 0.5, brevity: 0.3),
                    apps: ["app.a": AppSnapshot(sampleCount: 60,
                                                tone: ToneScores(formality: 0.8, warmth: 0.2, brevity: 0.9),
                                                phrases: ["thanks for the update"])],
                    overrides: .neutral)
}
private func neutralExpected(_ before: String) -> String {
    PromptAssembler().assemble(textBeforeCaret: before).fullText
}
private func styledExpected(_ snap: ProfileSnapshot, bundle: String, before: String) -> String {
    PromptAssembler(system: StyleDescriptor.render(snapshot: snap, bundleID: bundle)!)
        .assemble(textBeforeCaret: before).fullText
}
private let kEsc: Int64 = 53

@Suite struct CoordinatorPersonalizationTests {
    @Test @MainActor func nilProfileCacheKeepsTodaysExactPromptBytes() async {
        let e = PromptCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil, capture: { ctxFor("app.a", "Thanks for") })
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.prompts.first?.fullText == neutralExpected("Thanks for"))
        #expect(e.prompts.first?.stablePrefix == PromptAssembler().scaffold)
    }
    @Test @MainActor func emptyCacheIsAlsoNeutral() async {
        let e = PromptCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil,
                                      capture: { ctxFor("app.a", "Thanks for") },
                                      profileCache: ProfileCache())
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.prompts.first?.fullText == neutralExpected("Thanks for"))
    }
    @Test @MainActor func coldStartSnapshotBelowThresholdIsNeutral() async {
        let cache = ProfileCache()
        cache.publish(ProfileSnapshot(version: 1, totalSamples: 3, global: nil, apps: [:],
                                      overrides: .neutral))
        let e = PromptCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil,
                                      capture: { ctxFor("app.a", "Thanks for") }, profileCache: cache)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.prompts.first?.fullText == neutralExpected("Thanks for"))
    }
    @Test @MainActor func activeSnapshotStylesTheSystemTurn() async {
        let cache = ProfileCache()
        let snap = activeSnapshot()
        cache.publish(snap)
        let e = PromptCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil,
                                      capture: { ctxFor("app.a", "Thanks for") }, profileCache: cache)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.prompts.first?.fullText == styledExpected(snap, bundle: "app.a", before: "Thanks for"))
    }
    @Test @MainActor func pinHoldsBytesAcrossSnapshotUpdates() async {
        // §7.5 byte-stability: a mid-session publish must NOT change the prompt prefix.
        let cache = ProfileCache()
        cache.publish(activeSnapshot(version: 1))
        let e = PromptCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil,
                                      capture: { ctxFor("app.a", "Thanks for") }, profileCache: cache)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        cache.publish(ProfileSnapshot(version: 2, totalSamples: 80,
                                      global: ToneScores(formality: 0.1, warmth: 0.9, brevity: 0.1),
                                      apps: [:], overrides: .neutral))
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.prompts.count == 2)
        #expect(e.prompts[0].fullText == e.prompts[1].fullText)
    }
    @Test @MainActor func focusInvalidationRepinsFromTheCurrentSnapshot() async {
        let cache = ProfileCache()
        let v1 = activeSnapshot(version: 1)
        cache.publish(v1)
        let e = PromptCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil,
                                      capture: { ctxFor("app.a", "Thanks for") }, profileCache: cache)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        let v2 = ProfileSnapshot(version: 2, totalSamples: 80,
                                 global: ToneScores(formality: 0.1, warmth: 0.9, brevity: 0.1),
                                 apps: [:], overrides: .neutral)
        cache.publish(v2)
        c._test_invalidateFocus()
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.prompts[0].fullText == styledExpected(v1, bundle: "app.a", before: "Thanks for"))
        #expect(e.prompts[1].fullText == styledExpected(v2, bundle: "app.a", before: "Thanks for"))
        #expect(e.prompts[0].fullText != e.prompts[1].fullText)
    }
    @Test @MainActor func bundleChangeMidSessionRepinsImmediately() async {
        // The Cmd-Tab race: the app-activation notification can arrive AFTER the first
        // keystroke in the new app, so the pin must re-validate against ctx.bundleID.
        let cache = ProfileCache()
        let snap = activeSnapshot()
        cache.publish(snap)
        let e = PromptCapturingEngine()
        var bundle = "app.a"
        let c = SuggestionCoordinator(engine: e, inserter: nil,
                                      capture: { ctxFor(bundle, "Thanks for") }, profileCache: cache)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        bundle = "app.b"          // switch WITHOUT _test_invalidateFocus — the race window
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.prompts[0].fullText == styledExpected(snap, bundle: "app.a", before: "Thanks for"))
        #expect(e.prompts[1].fullText == styledExpected(snap, bundle: "app.b", before: "Thanks for"))
        #expect(e.prompts[0].fullText != e.prompts[1].fullText)
    }
    @Test @MainActor func prepareForProfileResetRepinsFromTheCurrentSnapshot() async {
        let cache = ProfileCache()
        let v1 = activeSnapshot(version: 1)
        cache.publish(v1)
        let e = PromptCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil,
                                      capture: { ctxFor("app.a", "Thanks for") }, profileCache: cache)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        cache.publish(ProfileSnapshot(version: 2, totalSamples: 0, global: nil, apps: [:],
                                      overrides: .neutral))   // the post-reset empty snapshot
        c.prepareForProfileReset()
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.prompts[0].fullText == styledExpected(v1, bundle: "app.a", before: "Thanks for"))
        #expect(e.prompts[1].fullText == neutralExpected("Thanks for"))
    }
    @Test @MainActor func dismissDoesNotClearThePin() async {
        // Esc (and type-over) end the SUGGESTION, not the focus session. If dismiss cleared
        // the pin, every post-accept snapshot publish would re-prefill on the next keystroke.
        let cache = ProfileCache()
        cache.publish(activeSnapshot(version: 1))
        let e = PromptCapturingEngine()
        let c = SuggestionCoordinator(engine: e, inserter: nil,
                                      capture: { ctxFor("app.a", "Thanks for") }, profileCache: cache)
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        _ = c.handleKey(code: kEsc, hasShift: false)      // .dismiss path
        cache.publish(ProfileSnapshot(version: 2, totalSamples: 80,
                                      global: ToneScores(formality: 0.1, warmth: 0.9, brevity: 0.1),
                                      apps: [:], overrides: .neutral))
        await c._test_requestSuggestion()
        await c._test_awaitInflight()
        #expect(e.prompts[0].fullText == e.prompts[1].fullText)   // pin survived the dismiss
    }
}
