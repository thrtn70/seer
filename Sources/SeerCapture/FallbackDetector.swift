import CoreGraphics
import SeerModel

/// Decides inline ghost text vs. a floating pill for a captured field (§4.4).
public enum FallbackDetector {
    /// Inline only when there is a valid caret rect, an active selected-range (so the field
    /// is a real editable text element), and the app is not on the known-bad (Electron/web)
    /// list. Otherwise a pill, anchored caret-point → mouse-point → window-top.
    public static func renderMode(
        caretRect: CGRect?,
        hasSelectedRange: Bool,
        bundleID: String,
        knownBadBundles: Set<String>,
        mousePoint: CGPoint?,
        windowTopAnchor: CGPoint?
    ) -> RenderMode {
        if let rect = caretRect, hasSelectedRange, !knownBadBundles.contains(bundleID) {
            return .inline(rect)
        }
        let anchor = caretRect.map { CGPoint(x: $0.minX, y: $0.minY) }
            ?? mousePoint
            ?? windowTopAnchor
            ?? .zero
        return .pill(anchor)
    }
}
