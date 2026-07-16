import CoreGraphics
import SeerModel

/// Pure placement math for overlay windows — no AppKit windowing, fully unit-tested.
/// Home of the carry-forward caret-baseline calibration.
public enum OverlayPlacement {
    /// Bottom-left origin (AppKit screen coords) for inline ghost text.
    ///
    /// AX reports the caret rect at the line-fragment TOP (~one line above the glyph
    /// baseline), so ghost text would float above the user's text. Drop it by the caret
    /// height to sit on the line. (Phase-0 LIVE-VERIFIED. Spec §4.7 prose says `midY`,
    /// but `minY - height` is the proven value — keep it.)
    public static func inlineOrigin(caretRect: CGRect, textSize: CGSize) -> CGPoint {
        CGPoint(x: caretRect.maxX, y: caretRect.minY - caretRect.height)
    }

    /// Gap (points) between the fallback anchor and the pill's bottom-left, so the pill
    /// does not sit directly under the cursor/anchor point.
    public static let pillGap: CGFloat = 6

    /// Bottom-left origin for a fallback pill anchored at `anchor`.
    public static func pillOrigin(anchor: CGPoint, textSize: CGSize) -> CGPoint {
        CGPoint(x: anchor.x + pillGap, y: anchor.y + pillGap)
    }

    /// Render-mode-agnostic dispatch: maps a `RenderMode` to a window origin.
    public static func origin(for mode: RenderMode, textSize: CGSize) -> CGPoint {
        switch mode {
        case let .inline(rect): return inlineOrigin(caretRect: rect, textSize: textSize)
        case let .pill(point): return pillOrigin(anchor: point, textSize: textSize)
        }
    }
}
