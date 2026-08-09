import Testing
@testable import SeerPersonalization

@Suite struct DecayTests {
    @Test func freshSampleWeighsOne() { #expect(Decay.weight(ageDays: 0) == 1.0) }
    @Test func halfLifeIs30Days() { #expect(abs(Decay.weight(ageDays: 30) - 0.5) < 1e-9) }
    @Test func sixtyDaysIsQuarter() { #expect(abs(Decay.weight(ageDays: 60) - 0.25) < 1e-9) }
    @Test func negativeAgeClampsToOne() { #expect(Decay.weight(ageDays: -5) == 1.0) }
    @Test func nonFiniteAgeIsZeroWeight() { #expect(Decay.weight(ageDays: .nan) == 0.0) }
    // A corrupt (infinite) timestamp must weigh zero, not dominate the corpus. The `-.infinity`
    // case is load-bearing: it distinguishes `isFinite` from a mere `!isNaN` guard.
    @Test func positiveInfinityAgeIsZeroWeight() { #expect(Decay.weight(ageDays: .infinity) == 0.0) }
    @Test func negativeInfinityAgeIsZeroWeight() { #expect(Decay.weight(ageDays: -.infinity) == 0.0) }
}
