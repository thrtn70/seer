import Testing
@testable import SeerSupport

@Suite struct LatencyClockTests {
    @Test func elapsedIsNonNegative() {
        let clock = LatencyClock()
        #expect(clock.elapsedMilliseconds() >= 0)
    }
    @Test func elapsedIsMonotonicNonDecreasing() {
        let clock = LatencyClock()
        let a = clock.elapsedMilliseconds()
        // busy a hair so the second read can't precede the first
        var x = 0; for i in 0..<10_000 { x &+= i }; _ = x
        let b = clock.elapsedMilliseconds()
        #expect(b >= a)
    }
}
