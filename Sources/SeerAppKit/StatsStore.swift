import Foundation

/// Stateless app-layer glue: applies coordinator stat events to the persisted DailyStats
/// (load → reduce → save per event) and serves day-aware snapshots for the menu.
/// Clock and calendar are injected for tests; production uses the defaults.
/// Callers are assumed to be a single main-actor writer (MenuController wiring) — the
/// underlying seer.stats.* keys are not written atomically.
public struct StatsStore {
    private let settings: AppSettings
    private let calendar: Calendar
    private let now: () -> Date

    public init(settings: AppSettings,
                calendar: Calendar = .current,
                now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    /// Records an accept of `words` words; ignored if `words <= 0` (a rejected event
    /// must not materialize an empty persisted DailyStats).
    public func recordAccept(words: Int) {
        guard words > 0 else { return }
        let eventDate = now()
        settings.dailyStats = current(asOf: eventDate).recording(wordsAccepted: words, on: eventDate, calendar: calendar)
    }

    /// Records one suggestion latency sample; ignored unless finite and >= 0.
    public func recordSuggestionLatency(ms: Double) {
        guard ms.isFinite, ms >= 0 else { return }
        let eventDate = now()
        settings.dailyStats = current(asOf: eventDate).recording(latencyMs: ms, on: eventDate, calendar: calendar)
    }

    /// Day-aware read for the menu: zeros/nil once the stored day is over.
    public func snapshot() -> StatsSnapshot {
        let readDate = now()
        return current(asOf: readDate).snapshot(asOf: readDate, calendar: calendar)
    }

    private func current(asOf date: Date) -> DailyStats {
        settings.dailyStats ?? DailyStats(dayKey: DailyStats.dayKey(for: date, calendar: calendar))
    }
}
