import Foundation

/// Recency weighting for corpus statistics: half-life 30 days, computed at recompute time
/// (never a background timer). Non-finite ages weigh zero (a corrupt timestamp mustn't
/// dominate the corpus); negative ages (clock skew) clamp to fresh.
public enum Decay {
    public static let halfLifeDays = 30.0
    public static func weight(ageDays: Double) -> Double {
        guard ageDays.isFinite else { return 0 }
        return pow(0.5, max(0, ageDays) / halfLifeDays)
    }
}
