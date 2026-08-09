import Testing
@testable import SeerPersonalization

@Suite struct ToneMappingTests {
    @Test func maxBrevityGivesLowTemperature() {
        #expect(abs(ToneMapping.autoTemperature(brevity: 1.0) - 0.25) < 1e-9)
    }
    @Test func minBrevityGivesHighTemperature() {
        #expect(abs(ToneMapping.autoTemperature(brevity: 0.0) - 0.45) < 1e-9)
    }
    @Test func midBrevityIsLinear() {
        #expect(abs(ToneMapping.autoTemperature(brevity: 0.5) - 0.35) < 1e-9)
    }
    @Test func resultAlwaysInsideHardBounds() {
        for b in [-5.0, -0.1, 0.0, 0.3, 1.0, 1.7, 99.0] {
            let t = ToneMapping.autoTemperature(brevity: b)
            #expect(t >= 0.2 && t <= 0.5)
        }
    }
    @Test func nonFiniteBrevityFallsToNeutral() {
        // Non-finite (NaN and ±infinity: isFinite == false) → treated as brevity 0.5 → 0.35.
        #expect(abs(ToneMapping.autoTemperature(brevity: .nan) - 0.35) < 1e-9)
        #expect(abs(ToneMapping.autoTemperature(brevity: .infinity) - 0.35) < 1e-9)
    }
}
