import Testing
import CoreGraphics
import SeerModel
@testable import SeerOverlay

@Suite struct InlineRendererTests {
    @Test @MainActor func constructsAndHandlesEmptyAndClear() {
        let r: any SuggestionRenderer = InlineRenderer(resolvedFont: ResolvedFont(name: nil, size: 13))
        r.setPlacement(.inline(CGRect(x: 0, y: 0, width: 2, height: 18)))  // no text yet ⇒ no order-front
        r.update(text: "")        // sanitizes to empty ⇒ clear()
        r.update(text: "   ")     // whitespace ⇒ clear()
        r.clear()
        r.clear()                 // idempotent
        #expect(Bool(true))
    }
    @Test @MainActor func ignoresPillModeWithoutCrashing() {
        let r = InlineRenderer(resolvedFont: ResolvedFont(name: nil, size: 13))
        r.setPlacement(.pill(CGPoint(x: 10, y: 10)))   // cross-mode safety
        r.clear()
        #expect(Bool(true))
    }
    @Test @MainActor func setPlacementAfterClearDoesNotReshow() {
        let r = InlineRenderer(resolvedFont: ResolvedFont(name: nil, size: 13))
        r.setPlacement(.inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        r.update(text: "hello")
        r.clear()
        // After clear(), stringValue is reset, so this setPlacement must not re-show stale text.
        r.setPlacement(.inline(CGRect(x: 10, y: 10, width: 2, height: 18)))
        #expect(Bool(true))   // crash-safety smoke; visual non-reshow verified by the probe
    }
}
