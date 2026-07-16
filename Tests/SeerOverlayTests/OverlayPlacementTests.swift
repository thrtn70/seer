import Testing
import CoreGraphics
import SeerModel
@testable import SeerOverlay

@Suite struct OverlayPlacementTests {
    @Test func inlineOriginAppliesPhase0Offset() {
        // x = caret right edge; y = caret bottom dropped by one caret height (baseline calibration).
        let caret = CGRect(x: 100, y: 500, width: 2, height: 18)
        let origin = OverlayPlacement.inlineOrigin(caretRect: caret, textSize: CGSize(width: 80, height: 18))
        #expect(origin == CGPoint(x: 102, y: 482))   // x: 100+2, y: 500-18
    }

    @Test func inlineOffsetScalesWithCaretHeight() {
        let caret = CGRect(x: 0, y: 200, width: 2, height: 40)
        let origin = OverlayPlacement.inlineOrigin(caretRect: caret, textSize: .zero)
        #expect(origin == CGPoint(x: 2, y: 160))      // y: 200-40
    }

    @Test func pillOriginAppliesGap() {
        let origin = OverlayPlacement.pillOrigin(anchor: CGPoint(x: 100, y: 200), textSize: .zero)
        #expect(origin == CGPoint(x: 106, y: 206))   // anchor + pillGap on both axes
    }

    @Test func originDispatchesInline() {
        let mode = RenderMode.inline(CGRect(x: 100, y: 500, width: 2, height: 18))
        #expect(OverlayPlacement.origin(for: mode, textSize: .zero) == CGPoint(x: 102, y: 482))
    }

    @Test func originDispatchesPill() {
        let mode = RenderMode.pill(CGPoint(x: 100, y: 200))
        #expect(OverlayPlacement.origin(for: mode, textSize: .zero) == CGPoint(x: 106, y: 206))
    }
}
