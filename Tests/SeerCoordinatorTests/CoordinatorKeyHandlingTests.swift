import Testing
import CoreGraphics
import SeerModel
import SeerInference
import SeerInsertion
@testable import SeerCoordinator

private final class MockEngine: InferenceEngine, @unchecked Sendable {
    let kind: EngineKind = .llamaCpp
    var isAvailable: Bool { true }
    func warmUp() async {}
    func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
}
@MainActor private final class SpyInserter: TextInserting {
    var inserted: [String] = []
    func insert(_ text: String, gate: KeystrokeGate) { inserted.append(text) }
}
private let kTab: Int64 = 48
private let kEsc: Int64 = 53

@Suite struct CoordinatorKeyHandlingTests {
    @MainActor private func make(_ inserter: SpyInserter) -> SuggestionCoordinator {
        SuggestionCoordinator(engine: MockEngine(), inserter: inserter, capture: { nil })
    }
    @Test @MainActor func idleKeyPassesThrough() {
        let c = make(SpyInserter())
        #expect(c.handleKey(code: kTab, hasShift: false) == false)
    }
    @Test @MainActor func showingTabAcceptsFirstChunkAndSwallows() {
        let spy = SpyInserter()
        let c = make(spy)
        c._test_setShowing(Suggestion(text: "issued a refund",
                                      chunks: ["issued ", "a ", "refund"], forPrefixHash: 1),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        let swallowed = c.handleKey(code: kTab, hasShift: false)
        #expect(swallowed == true)
        #expect(spy.inserted == ["issued "])
    }
    @Test @MainActor func showingEscDismissesAndSwallows() {
        let c = make(SpyInserter())
        c._test_setShowing(Suggestion(text: "x", chunks: ["x"], forPrefixHash: 1),
                           mode: .inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        #expect(c.handleKey(code: kEsc, hasShift: false) == true)
        #expect(c.testState == .idle)
    }
}
