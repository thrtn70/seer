import CoreGraphics

public enum Geometry {
    /// Flip a y-coordinate from AX global space (origin top-left of the primary
    /// display, y grows down) to AppKit screen space (origin bottom-left, y grows up).
    public static func flipY(axTop: CGFloat, height: CGFloat, primaryHeight: CGFloat) -> CGFloat {
        primaryHeight - axTop - height
    }

    /// A caret rect is usable only if it is non-empty, sanely sized, and on the primary screen.
    public static func isValid(_ rect: CGRect, primaryFrame: CGRect) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        guard rect.width < 10_000, rect.height < 10_000 else { return false }
        return primaryFrame.intersects(rect)
    }
}
