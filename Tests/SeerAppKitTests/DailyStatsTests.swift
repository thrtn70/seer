import Testing
import Foundation
@testable import SeerAppKit

@Suite struct DailyStatsTests {
    private func cal(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, in c: Calendar) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func dayKeyIsZeroPaddedISO() {
        let c = cal("America/Los_Angeles")
        #expect(DailyStats.dayKey(for: date(2026, 7, 5, 12, 0, in: c), calendar: c) == "2026-07-05")
    }
    @Test func dayKeyFollowsCalendarTimeZone() {
        let la = cal("America/Los_Angeles"), bkk = cal("Asia/Bangkok")
        let instant = date(2026, 7, 17, 23, 30, in: la)   // 23:30 LA = 13:30 next day BKK
        #expect(DailyStats.dayKey(for: instant, calendar: la) == "2026-07-17")
        #expect(DailyStats.dayKey(for: instant, calendar: bkk) == "2026-07-18")
    }
    @Test func wordsAccumulateWithinSameDay() {
        let c = cal("America/Los_Angeles")
        let noon = date(2026, 7, 17, 12, 0, in: c)
        let s = DailyStats(dayKey: "2026-07-17")
            .recording(wordsAccepted: 3, on: noon, calendar: c)
            .recording(wordsAccepted: 2, on: date(2026, 7, 17, 18, 0, in: c), calendar: c)
        #expect(s.wordsAccepted == 5)
        #expect(s.dayKey == "2026-07-17")
    }
    @Test func latencyAccumulatesSumAndCount() {
        let c = cal("America/Los_Angeles")
        let noon = date(2026, 7, 17, 12, 0, in: c)
        let s = DailyStats(dayKey: "2026-07-17")
            .recording(latencyMs: 100, on: noon, calendar: c)
            .recording(latencyMs: 300, on: noon, calendar: c)
        #expect(s.latencySumMs == 400)
        #expect(s.latencyCount == 2)
    }
    @Test func snapshotAveragesLatency() {
        let c = cal("America/Los_Angeles")
        let noon = date(2026, 7, 17, 12, 0, in: c)
        let s = DailyStats(dayKey: "2026-07-17")
            .recording(latencyMs: 100, on: noon, calendar: c)
            .recording(latencyMs: 300, on: noon, calendar: c)
        #expect(s.snapshot(asOf: noon, calendar: c).averageLatencyMs == 200.0)
    }
    @Test func snapshotWithNoLatencySamplesHasNilAverage() {
        let c = cal("America/Los_Angeles")
        let noon = date(2026, 7, 17, 12, 0, in: c)
        let s = DailyStats(dayKey: "2026-07-17").recording(wordsAccepted: 1, on: noon, calendar: c)
        #expect(s.snapshot(asOf: noon, calendar: c).averageLatencyMs == nil)
    }
    @Test func emptyDayHasZeroWordsAndNilAverage() {
        let c = cal("America/Los_Angeles")
        let noon = date(2026, 7, 17, 12, 0, in: c)
        let snap = DailyStats(dayKey: "2026-07-17").snapshot(asOf: noon, calendar: c)
        #expect(snap.wordsToday == 0)
        #expect(snap.averageLatencyMs == nil)
    }
    @Test func midnightRolloverResetsAndCountsNewEvent() {
        let c = cal("America/Los_Angeles")
        let s = DailyStats(dayKey: "2026-07-17")
            .recording(wordsAccepted: 5, on: date(2026, 7, 17, 23, 59, in: c), calendar: c)
            .recording(latencyMs: 80, on: date(2026, 7, 17, 23, 59, in: c), calendar: c)
            .recording(wordsAccepted: 2, on: date(2026, 7, 18, 0, 0, in: c), calendar: c)
        #expect(s.dayKey == "2026-07-18")
        #expect(s.wordsAccepted == 2)
        #expect(s.latencyCount == 0)
        #expect(s.latencySumMs == 0)
    }
    @Test func clockMovingBackwardsResetsToCurrentDay() {
        let c = cal("America/Los_Angeles")
        let s = DailyStats(dayKey: "2026-07-18")
            .recording(wordsAccepted: 9, on: date(2026, 7, 18, 9, 0, in: c), calendar: c)
            .recording(wordsAccepted: 1, on: date(2026, 7, 17, 12, 0, in: c), calendar: c)
        #expect(s.dayKey == "2026-07-17")
        #expect(s.wordsAccepted == 1)
    }
    @Test func snapshotOnStaleDayShowsZeros() {
        let c = cal("America/Los_Angeles")
        let s = DailyStats(dayKey: "2026-07-17")
            .recording(wordsAccepted: 9, on: date(2026, 7, 17, 12, 0, in: c), calendar: c)
            .recording(latencyMs: 50, on: date(2026, 7, 17, 12, 0, in: c), calendar: c)
        let snap = s.snapshot(asOf: date(2026, 7, 18, 8, 0, in: c), calendar: c)
        #expect(snap.wordsToday == 0)
        #expect(snap.averageLatencyMs == nil)
    }
    @Test func wordsMenuLinePluralizes() {
        #expect(StatsSnapshot(wordsToday: 0, averageLatencyMs: nil).wordsMenuLine == "Accepted today: 0 words")
        #expect(StatsSnapshot(wordsToday: 1, averageLatencyMs: nil).wordsMenuLine == "Accepted today: 1 word")
        #expect(StatsSnapshot(wordsToday: 128, averageLatencyMs: nil).wordsMenuLine == "Accepted today: 128 words")
    }
    @Test func latencyMenuLineFormatsAndRounds() {
        #expect(StatsSnapshot(wordsToday: 0, averageLatencyMs: nil).latencyMenuLine == "Avg latency: —")
        #expect(StatsSnapshot(wordsToday: 0, averageLatencyMs: 41.6).latencyMenuLine == "Avg latency: 42 ms")
        #expect(StatsSnapshot(wordsToday: 0, averageLatencyMs: 41.4).latencyMenuLine == "Avg latency: 41 ms")
    }
    @Test func nonPositiveWordCountsAreIgnored() {
        let c = cal("America/Los_Angeles")
        let noon = date(2026, 7, 17, 12, 0, in: c)
        let s = DailyStats(dayKey: "2026-07-17")
            .recording(wordsAccepted: 0, on: noon, calendar: c)
            .recording(wordsAccepted: -3, on: noon, calendar: c)
        #expect(s == DailyStats(dayKey: "2026-07-17"))
    }
    @Test func negativeAndNonFiniteLatencySamplesAreIgnored() {
        let c = cal("America/Los_Angeles")
        let noon = date(2026, 7, 17, 12, 0, in: c)
        let s = DailyStats(dayKey: "2026-07-17")
            .recording(latencyMs: -5, on: noon, calendar: c)
            .recording(latencyMs: .nan, on: noon, calendar: c)
            .recording(latencyMs: .infinity, on: noon, calendar: c)
        #expect(s.latencyCount == 0)
        #expect(s.latencySumMs == 0)
    }
    @Test func latencyMenuLineTreatsNonFiniteAsNoData() {
        #expect(StatsSnapshot(wordsToday: 0, averageLatencyMs: .nan).latencyMenuLine == "Avg latency: —")
        #expect(StatsSnapshot(wordsToday: 0, averageLatencyMs: .infinity).latencyMenuLine == "Avg latency: —")
    }
    @Test func latencyMenuLineTreatsUnrepresentableMagnitudeAsNoData() {
        #expect(StatsSnapshot(wordsToday: 0, averageLatencyMs: 1e19).latencyMenuLine == "Avg latency: —")
    }
}
