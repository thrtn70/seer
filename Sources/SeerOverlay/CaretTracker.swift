import CoreGraphics

/// Pure caret-tracking decisions. The Timer/RunLoop wiring lives in the probe; the
/// cadence constant and the "should I move the window?" decision live here.
public enum CaretTracker {
    /// 5 Hz caret-tracking cadence (seconds).
    public static let interval: Double = 0.2

    /// Dead-zone (points): ignore sub-threshold jitter so the panel doesn't redraw
    /// 5×/sec against the ~8 ms render budget.
    public static let deadZone: CGFloat = 2

    /// Whether the overlay should re-anchor given old/new caret rects.
    /// nil→rect: appear; rect→nil: disappear; moved more than `deadZone` on either axis: move.
    public static func shouldMove(from old: CGRect?, to new: CGRect?) -> Bool {
        switch (old, new) {
        case (nil, nil): return false
        case (nil, _?), (_?, nil): return true
        case let (a?, b?):
            return abs(a.origin.x - b.origin.x) > deadZone || abs(a.origin.y - b.origin.y) > deadZone
        }
    }
}
