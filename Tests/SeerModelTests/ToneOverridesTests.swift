import Testing
import SeerModel

@Suite struct ToneOverridesTests {
    @Test func sanitizesNonFiniteToNil() {
        let o = ToneOverrides(formality: .nan, warmth: .infinity, brevity: -.infinity)
        #expect(o == .neutral)
    }
    @Test func sanitizesOutOfRangeToNil() {
        #expect(ToneOverrides(formality: -0.1, warmth: 1.1, brevity: 2000) == .neutral)
    }
    @Test func keepsValidValuesIncludingBounds() {
        let o = ToneOverrides(formality: 0.0, warmth: 1.0, brevity: 0.5)
        #expect(o.formality == 0.0 && o.warmth == 1.0 && o.brevity == 0.5)
        #expect(o != .neutral)
    }
    @Test func negativeZeroNormalizesToPlusZero() {
        // -0.0 is inside [0,1] and == 0.0, but JSON-encodes as "-0" — two ==-equal pins
        // must produce identical export bytes, so sanitize normalizes the sign.
        let o = ToneOverrides(formality: -0.0, warmth: nil, brevity: nil)
        #expect(o.formality?.sign == .plus)
    }
    @Test func equatableIsSafeAfterSanitization() {
        // NaN never survives construction, so == can't be broken by a NaN payload.
        let a = ToneOverrides(formality: .nan, warmth: 0.5, brevity: nil)
        let b = ToneOverrides(formality: .nan, warmth: 0.5, brevity: nil)
        #expect(a == b)
    }
}
