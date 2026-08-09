import Testing
import CoreGraphics
import Foundation
import SeerModel
import SeerInference
import SeerInsertion
import SeerPersonalization
@testable import SeerCoordinator

private final class NoEngine: InferenceEngine, @unchecked Sendable {
    let kind: EngineKind = .llamaCpp
    var isAvailable: Bool { true }
    func warmUp() async {}
    func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
@MainActor private final class Spy: TextInserting {
    private(set) var ins: [String] = []
    func insert(_ text: String, gate: KeystrokeGate) { ins.append(text) }
}
@MainActor private final class Recorder: TextInserting {
    var events: [String] = []
    func insert(_ text: String, gate: KeystrokeGate) { events.append("insert") }
}
@MainActor
private func learnCtx(_ before: String = "Thanks for", bundle: String = "com.apple.TextEdit",
                      subrole: String? = nil) -> CaptureContext {
    CaptureContext(bundleID: bundle, focusedRole: "AXTextArea", focusedSubrole: subrole,
                   textBeforeCaret: before, textAfterCaret: "", selectionLength: 0,
                   caretRect: CGRect(x: 10, y: 10, width: 2, height: 18),
                   prefixHash: 7, capturedAt: ContinuousClock().now)
}
private let kTab: Int64 = 48
private let kEsc: Int64 = 53
private func sug() -> Suggestion {
    Suggestion(text: "issued a refund", chunks: ["issued ", "a ", "refund"], forPrefixHash: 7)
}
@MainActor
private func pollUntil(deadline: Duration = .seconds(2),
                       _ condition: @MainActor () -> Bool) async {
    let clock = ContinuousClock()
    let end = clock.now.advanced(by: deadline)
    while !condition() && clock.now < end {
        try? await Task.sleep(for: .milliseconds(1))
    }
}

@Suite struct CoordinatorLearnTests {
    @Test @MainActor func wholeLineAcceptFiresOneSample() {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(), capture: { learnCtx() })
        var samples: [AcceptedSample] = []
        c.onLearn = { samples.append($0) }
        c._test_setShowing(sug(), mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)),
                           ctx: learnCtx())
        _ = c.handleKey(code: kTab, hasShift: true)
        #expect(samples.count == 1)
        #expect(samples.first?.completion == "issued a refund")
        #expect(samples.first?.bundleID == "com.apple.TextEdit")
        #expect(samples.first?.beforeCaret == "Thanks for")
        #expect(samples.first?.focusedSubrole == nil)
    }
    @Test @MainActor func perWordAcceptsAccumulateIntoOneSample() async {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(),
                                      capture: { learnCtx() }, reanchorDelay: 0)
        var samples: [AcceptedSample] = []
        c.onLearn = { samples.append($0) }
        c._test_setShowing(sug(), mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)),
                           ctx: learnCtx())
        _ = c.handleKey(code: kTab, hasShift: false)          // "issued "
        #expect(samples.isEmpty)                              // suggestion still live
        await pollUntil { c.testState == .showing }
        _ = c.handleKey(code: kTab, hasShift: false)          // "a "
        #expect(samples.isEmpty)
        await pollUntil { c.testState == .showing }
        _ = c.handleKey(code: kTab, hasShift: false)          // "refund" → exhausted → flush
        #expect(samples.count == 1)
        #expect(samples.first?.completion == "issued a refund")
    }
    @Test @MainActor func typeOverAfterPartialAcceptFlushesThePartial() async {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(),
                                      capture: { learnCtx() }, reanchorDelay: 0)
        var samples: [AcceptedSample] = []
        c.onLearn = { samples.append($0) }
        c._test_setShowing(sug(), mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)),
                           ctx: learnCtx())
        _ = c.handleKey(code: kTab, hasShift: false)          // "issued "
        await pollUntil { c.testState == .showing }
        _ = c.handleKey(code: 0, hasShift: false)             // 'a' → typeOverDismiss
        #expect(samples.count == 1)
        #expect(samples.first?.completion == "issued ")
    }
    @Test @MainActor func escWithoutAnyAcceptLearnsNothing() {
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(), capture: { learnCtx() })
        var samples: [AcceptedSample] = []
        c.onLearn = { samples.append($0) }
        c._test_setShowing(sug(), mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)),
                           ctx: learnCtx())
        _ = c.handleKey(code: kEsc, hasShift: false)
        #expect(samples.isEmpty)
    }
    @Test @MainActor func nilContextMeansNoLearnButInsertStillWorks() {
        // Every pre-existing accept test drives _test_setShowing without a ctx — the nil
        // guard is what keeps them green and learning silent.
        let spy = Spy()
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: spy, capture: { learnCtx() })
        var samples: [AcceptedSample] = []
        c.onLearn = { samples.append($0) }
        c._test_setShowing(sug(), mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        _ = c.handleKey(code: kTab, hasShift: true)
        #expect(spy.ins == ["issued a refund"])
        #expect(samples.isEmpty)
    }
    @Test @MainActor func secureSubroleNeverLearns() {
        // Defense in depth (§6): upstream capture already refuses secure fields, but if a
        // context ever carried the subrole, the coordinator must not emit a sample.
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(), capture: { learnCtx() })
        var samples: [AcceptedSample] = []
        c.onLearn = { samples.append($0) }
        c._test_setShowing(sug(), mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)),
                           ctx: learnCtx(subrole: "AXSecureTextField"))
        _ = c.handleKey(code: kTab, hasShift: true)
        #expect(samples.isEmpty)
    }
    @Test @MainActor func learnFiresAfterInsertAndStatsCallback() {
        let rec = Recorder()
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: rec, capture: { learnCtx() })
        c.onAccept = { _ in rec.events.append("accept") }
        c.onLearn = { _ in rec.events.append("learn") }
        c._test_setShowing(sug(), mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)),
                           ctx: learnCtx())
        _ = c.handleKey(code: kTab, hasShift: true)
        #expect(rec.events == ["insert", "accept", "learn"])
    }
    @Test @MainActor func prepareForProfileResetDiscardsPendingLearnWithoutFiring() async {
        // RED-verifiable: an implementation that only calls invalidateFocusSession() reaches
        // dismiss() → flushPendingLearn() → onLearn and this fails — resurrecting a sample
        // into the store the caller is about to reset.
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(),
                                      capture: { learnCtx() }, reanchorDelay: 0)
        var samples: [AcceptedSample] = []
        c.onLearn = { samples.append($0) }
        c._test_setShowing(sug(), mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)),
                           ctx: learnCtx())
        _ = c.handleKey(code: kTab, hasShift: false)          // partial accept arms pendingLearn
        await pollUntil { c.testState == .showing }
        c.prepareForProfileReset()
        #expect(samples.isEmpty)
    }
    @Test @MainActor func beforeCaretIsCappedAt200() {
        let long = String(repeating: "y", count: 450)
        let c = SuggestionCoordinator(engine: NoEngine(), inserter: Spy(), capture: { learnCtx() })
        var samples: [AcceptedSample] = []
        c.onLearn = { samples.append($0) }
        c._test_setShowing(sug(), mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)),
                           ctx: learnCtx(long))
        _ = c.handleKey(code: kTab, hasShift: true)
        #expect(samples.first?.beforeCaret.count == 200)
    }
}
