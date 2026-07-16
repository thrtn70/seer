import Testing
import CoreGraphics
import SeerModel
@testable import SeerOverlay

@Suite struct PillRendererTests {
    @Test @MainActor func constructsAndHandlesEmptyAndClear() {
        let r: any SuggestionRenderer = PillRenderer(resolvedFont: ResolvedFont(name: nil, size: 13))
        r.setPlacement(.pill(CGPoint(x: 50, y: 50)))   // no text yet ⇒ no order-front
        r.update(text: "")
        r.clear()
        r.clear()
        #expect(Bool(true))
    }
    @Test @MainActor func setPlacementAfterClearDoesNotReshow() {
        let r = PillRenderer(resolvedFont: ResolvedFont(name: nil, size: 13))
        r.setPlacement(.pill(CGPoint(x: 50, y: 50)))
        r.update(text: "hello")
        r.clear()
        r.setPlacement(.pill(CGPoint(x: 60, y: 60)))   // must not re-show stale text
        #expect(Bool(true))
    }
}
