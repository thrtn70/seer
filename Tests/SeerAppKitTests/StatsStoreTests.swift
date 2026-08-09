import Testing
import Foundation
@testable import SeerAppKit

@Suite struct StatsStoreTests {
    private final class FakeClock {
        var now: Date
        init(_ d: Date) { now = d }
    }
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    private func freshDefaults() -> UserDefaults {
        let name = "seer.test.\(UInt64.random(in: 0...(.max)))"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        Self.cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    private func store(_ settings: AppSettings, _ clock: FakeClock) -> StatsStore {
        StatsStore(settings: settings, calendar: Self.cal, now: { clock.now })
    }

    @Test func snapshotOnFreshDefaultsIsEmpty() {
        let snap = store(AppSettings(defaults: freshDefaults()), FakeClock(date(2026, 7, 17, 10, 0))).snapshot()
        #expect(snap.wordsToday == 0)
        #expect(snap.averageLatencyMs == nil)
    }
    @Test func firstAcceptCreatesTodayStats() {
        let s = AppSettings(defaults: freshDefaults())
        store(s, FakeClock(date(2026, 7, 17, 10, 0))).recordAccept(words: 3)
        #expect(s.dailyStats?.dayKey == "2026-07-17")
        #expect(s.dailyStats?.wordsAccepted == 3)
    }
    @Test func acceptsAccumulate() {
        let s = AppSettings(defaults: freshDefaults())
        let st = store(s, FakeClock(date(2026, 7, 17, 10, 0)))
        st.recordAccept(words: 3)
        st.recordAccept(words: 1)
        #expect(st.snapshot().wordsToday == 4)
    }
    @Test func latencyAccumulatesAndAverages() {
        let s = AppSettings(defaults: freshDefaults())
        let st = store(s, FakeClock(date(2026, 7, 17, 10, 0)))
        st.recordSuggestionLatency(ms: 10)
        st.recordSuggestionLatency(ms: 30)
        #expect(st.snapshot().averageLatencyMs == 20.0)
    }
    @Test func zeroWordAcceptIsIgnored() {
        let s = AppSettings(defaults: freshDefaults())
        store(s, FakeClock(date(2026, 7, 17, 10, 0))).recordAccept(words: 0)
        #expect(s.dailyStats == nil)
    }
    @Test func statsSurviveRelaunch() {
        let d = freshDefaults()
        let clock = FakeClock(date(2026, 7, 17, 10, 0))
        store(AppSettings(defaults: d), clock).recordAccept(words: 4)
        // "relaunch": a brand-new store over the same defaults
        #expect(store(AppSettings(defaults: d), clock).snapshot().wordsToday == 4)
    }
    @Test func eventAfterMidnightStartsFreshDay() {
        let s = AppSettings(defaults: freshDefaults())
        let clock = FakeClock(date(2026, 7, 17, 23, 59))
        let st = store(s, clock)
        st.recordAccept(words: 5)
        clock.now = date(2026, 7, 18, 0, 1)
        st.recordAccept(words: 2)
        #expect(st.snapshot().wordsToday == 2)
        #expect(s.dailyStats?.dayKey == "2026-07-18")
    }
    @Test func latencyAfterMidnightStartsFreshDay() {
        let s = AppSettings(defaults: freshDefaults())
        let clock = FakeClock(date(2026, 7, 17, 23, 59))
        let st = store(s, clock)
        st.recordSuggestionLatency(ms: 100)
        clock.now = date(2026, 7, 18, 0, 1)
        st.recordSuggestionLatency(ms: 30)
        #expect(st.snapshot().averageLatencyMs == 30.0)
        #expect(s.dailyStats?.latencyCount == 1)
    }
    @Test func invalidLatencySampleDoesNotCreateStats() {
        let s = AppSettings(defaults: freshDefaults())
        let st = store(s, FakeClock(date(2026, 7, 17, 10, 0)))
        st.recordSuggestionLatency(ms: -1)
        st.recordSuggestionLatency(ms: .nan)
        #expect(s.dailyStats == nil)
    }
    @Test func snapshotAfterMidnightIsEmptyWithoutEvents() {
        let s = AppSettings(defaults: freshDefaults())
        let clock = FakeClock(date(2026, 7, 17, 12, 0))
        let st = store(s, clock)
        st.recordAccept(words: 7)
        st.recordSuggestionLatency(ms: 42)
        clock.now = date(2026, 7, 18, 8, 0)
        let snap = st.snapshot()
        #expect(snap.wordsToday == 0)
        #expect(snap.averageLatencyMs == nil)
    }
}
