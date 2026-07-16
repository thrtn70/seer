import CoreGraphics

/// Caret-rect coordinate math shared by capture (and later, render).
public enum CaretGeometry {
    /// Flip a y-coordinate from AX global space (origin top-left of the primary display,
    /// y grows down) to AppKit screen space (origin bottom-left, y grows up).
    public static func flipY(axTop: CGFloat, height: CGFloat, primaryHeight: CGFloat) -> CGFloat {
        primaryHeight - axTop - height
    }

    /// Maximum allowed caret dimension in points. Anything larger is considered a bogus AX value.
    private static let maxDimension: CGFloat = 10_000

    /// A caret rect is usable only if non-empty, sanely sized, and on the primary screen.
    ///
    /// Uses `rect.size.width` / `rect.size.height` (raw storage) rather than the computed
    /// `rect.width` / `rect.height` accessors, because Core Graphics computes width/height
    /// as `abs(size.width)` — meaning a rect with `size.width == -2` reports `width == 2`
    /// and would silently pass a `> 0` guard. Checking `.size` directly rejects
    /// negative-dimension rects as the contract requires.
    public static func isValid(_ rect: CGRect, primaryFrame: CGRect) -> Bool {
        guard rect.size.width > 0, rect.size.height > 0 else { return false }
        guard rect.size.width < maxDimension, rect.size.height < maxDimension else { return false }
        return primaryFrame.intersects(rect)
    }
}
