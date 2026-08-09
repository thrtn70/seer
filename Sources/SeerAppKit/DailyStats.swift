import Foundation

/// One local-calendar day of accept/latency stats. Pure value: reducers return a new
/// value, rolling over to a fresh day whenever the event date's day key differs from
/// the stored one (covers both midnight and the clock moving backwards). No wall-clock
/// reads — dates and calendar are injected by the caller. Non-positive word counts and
/// negative/non-finite latency samples are ignored (boundary hardening — persistence
/// can be hand-edited via `defaults write`).
public struct DailyStats: Equatable, Sendable {
    public let dayKey: String            // "2026-07-17", local-calendar day
    public let wordsAccepted: Int
    public let latencySumMs: Double      // sum+count (exact, round-trippable), not a running average
    public let latencyCount: Int

    public init(dayKey: String, wordsAccepted: Int = 0, latencySumMs: Double = 0, latencyCount: Int = 0) {
        self.dayKey = dayKey
        self.wordsAccepted = wordsAccepted
        self.latencySumMs = latencySumMs
        self.latencyCount = latencyCount
    }

    /// Zero-padded "yyyy-MM-dd" from calendar components (no DateFormatter — locale-free).
    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func recording(wordsAccepted count: Int, on date: Date, calendar: Calendar) -> DailyStats {
        guard count > 0 else { return self }
        let base = rolled(to: date, calendar: calendar)
        return DailyStats(dayKey: base.dayKey, wordsAccepted: base.wordsAccepted + count,
                          latencySumMs: base.latencySumMs, latencyCount: base.latencyCount)
    }

    public func recording(latencyMs ms: Double, on date: Date, calendar: Calendar) -> DailyStats {
        guard ms.isFinite, ms >= 0 else { return self }
        let base = rolled(to: date, calendar: calendar)
        return DailyStats(dayKey: base.dayKey, wordsAccepted: base.wordsAccepted,
                          latencySumMs: base.latencySumMs + ms, latencyCount: base.latencyCount + 1)
    }

    /// Display-ready view AS OF `date`: zeros/nil if the stored day is not `date`'s day,
    /// so a menu opened after midnight shows fresh stats without any recorded event.
    public func snapshot(asOf date: Date, calendar: Calendar) -> StatsSnapshot {
        guard dayKey == Self.dayKey(for: date, calendar: calendar) else {
            return StatsSnapshot(wordsToday: 0, averageLatencyMs: nil)
        }
        return StatsSnapshot(wordsToday: wordsAccepted,
                             averageLatencyMs: latencyCount > 0 ? latencySumMs / Double(latencyCount) : nil)
    }

    private func rolled(to date: Date, calendar: Calendar) -> DailyStats {
        let key = Self.dayKey(for: date, calendar: calendar)
        return key == dayKey ? self : DailyStats(dayKey: key)
    }
}

/// Display-ready stats for the menu.
public struct StatsSnapshot: Equatable, Sendable {
    public let wordsToday: Int
    public let averageLatencyMs: Double?   // nil when no samples today

    public init(wordsToday: Int, averageLatencyMs: Double?) {
        self.wordsToday = wordsToday
        self.averageLatencyMs = averageLatencyMs
    }

    public var wordsMenuLine: String {
        "Accepted today: \(wordsToday) \(wordsToday == 1 ? "word" : "words")"
    }
    /// Whole-ms rounding; no unit switching above 1000 ms (a big number SHOULD look odd).
    public var latencyMenuLine: String {
        guard let ms = averageLatencyMs, ms.isFinite, let whole = Int(exactly: ms.rounded()) else { return "Avg latency: —" }
        return "Avg latency: \(whole) ms"
    }
}
