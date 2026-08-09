import Testing
import Foundation
@testable import SeerAppKit
import SeerModel
import SeerOverlay

@Suite struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "seer.test.\(UInt64.random(in: 0...(.max)))"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    @Test func enabledDefaultsTrue() {
        #expect(AppSettings(defaults: freshDefaults()).enabled == true)
    }
    @Test func autoTemperatureDefaultsOff() {
        // Default OFF preserves the live-verified Phase-11 behavior (§7.4 amendment).
        #expect(AppSettings(defaults: freshDefaults()).autoTemperature == false)
    }
    @Test func autoTemperatureRoundTrips() {
        let s = AppSettings(defaults: freshDefaults())
        s.autoTemperature = true
        #expect(s.autoTemperature == true)
        s.autoTemperature = false
        #expect(s.autoTemperature == false)
    }
    @Test func autoTemperatureJunkReadsAsOff() {
        let d = freshDefaults()
        d.set("yes please", forKey: "seer.autoTemperature")
        #expect(AppSettings(defaults: d).autoTemperature == false)
    }
    @Test func toneOverridesDefaultToNeutral() {
        #expect(AppSettings(defaults: freshDefaults()).toneOverrides == .neutral)
    }
    @Test func toneOverridesRoundTrip() {
        let s = AppSettings(defaults: freshDefaults())
        s.toneOverrides = ToneOverrides(formality: 0.7, warmth: nil, brevity: 0.2)
        #expect(s.toneOverrides == ToneOverrides(formality: 0.7, warmth: nil, brevity: 0.2))
    }
    @Test func toneOverrideNilAxisClearsItsKey() {
        let s = AppSettings(defaults: freshDefaults())
        s.toneOverrides = ToneOverrides(formality: 0.7, warmth: 0.4, brevity: 0.2)
        s.toneOverrides = ToneOverrides(formality: nil, warmth: 0.4, brevity: 0.2)
        #expect(s.toneOverrides.formality == nil)
        #expect(s.toneOverrides.warmth == 0.4)
    }
    @Test func toneOverridesJunkReadsAsNil() {
        let d = freshDefaults()
        d.set("spicy", forKey: "seer.toneOverrideFormality")
        d.set(7.5, forKey: "seer.toneOverrideWarmth")     // out of [0,1]
        d.set(-3.0, forKey: "seer.toneOverrideBrevity")
        #expect(AppSettings(defaults: d).toneOverrides == .neutral)
    }
    @Test func enabledRoundTrips() {
        let s = AppSettings(defaults: freshDefaults())
        s.enabled = false
        #expect(s.enabled == false)
    }
    @Test func pausedBundlesRoundTrip() {
        let s = AppSettings(defaults: freshDefaults())
        s.pausedBundles = ["com.apple.TextEdit", "com.foo.bar"]
        #expect(s.pausedBundles == ["com.apple.TextEdit", "com.foo.bar"])
    }
    @Test func onboardingDefaultsFalse() {
        #expect(AppSettings(defaults: freshDefaults()).onboardingComplete == false)
    }
    @Test func settingsDeepLinkURLs() {
        #expect(SystemSettingsLink.accessibility.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        #expect(SystemSettingsLink.inputMonitoring.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }
    @Test func permissionsAllGrantedLogic() {
        #expect(PermissionsStatus(accessibility: true, inputMonitoring: true).allGranted == true)
        #expect(PermissionsStatus(accessibility: true, inputMonitoring: false).allGranted == false)
    }
    @Test func dailyStatsDefaultsToNil() {
        #expect(AppSettings(defaults: freshDefaults()).dailyStats == nil)
    }
    @Test func dailyStatsRoundTripsAllFields() {
        let s = AppSettings(defaults: freshDefaults())
        s.dailyStats = DailyStats(dayKey: "2026-07-17", wordsAccepted: 42, latencySumMs: 123.5, latencyCount: 3)
        #expect(s.dailyStats == DailyStats(dayKey: "2026-07-17", wordsAccepted: 42, latencySumMs: 123.5, latencyCount: 3))
    }
    @Test func dailyStatsNilAssignmentClears() {
        let s = AppSettings(defaults: freshDefaults())
        s.dailyStats = DailyStats(dayKey: "2026-07-17", wordsAccepted: 1, latencySumMs: 10, latencyCount: 1)
        s.dailyStats = nil
        #expect(s.dailyStats == nil)
    }
    @Test func dailyStatsReadClampsHandEditedNegatives() {
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        d.set("2026-07-17", forKey: "seer.stats.dayKey")
        d.set(-5, forKey: "seer.stats.wordsAccepted")
        d.set(-10.0, forKey: "seer.stats.latencySumMs")
        d.set(-2, forKey: "seer.stats.latencyCount")
        #expect(s.dailyStats == DailyStats(dayKey: "2026-07-17"))
    }
    @Test func dailyStatsReadSanitizesNonFiniteLatencySum() {
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        d.set("2026-07-17", forKey: "seer.stats.dayKey")
        d.set(Double.infinity, forKey: "seer.stats.latencySumMs")
        #expect(s.dailyStats == DailyStats(dayKey: "2026-07-17"))
    }
    @Test func dailyStatsReadCapsAbsurdMagnitudes() {
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        d.set("2026-07-17", forKey: "seer.stats.dayKey")
        d.set(Int.max, forKey: "seer.stats.wordsAccepted")
        d.set(1e19, forKey: "seer.stats.latencySumMs")
        d.set(Int.max, forKey: "seer.stats.latencyCount")
        let stats = s.dailyStats
        #expect(stats?.wordsAccepted == 1_000_000)
        #expect(stats?.latencySumMs == 86_400_000)
        #expect(stats?.latencyCount == 1_000_000)
    }
    // MARK: Generation settings (Phase 11)
    @Test func temperatureDefaults() {
        #expect(AppSettings(defaults: freshDefaults()).temperature == 0.2)
    }
    @Test func temperatureRoundTrips() {
        let s = AppSettings(defaults: freshDefaults())
        s.temperature = 0.35
        #expect(s.temperature == 0.35)
    }
    @Test func temperatureReadClampsOutOfRange() {
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        d.set(0.05, forKey: "seer.temperature")
        #expect(s.temperature == 0.2)
        d.set(3.0, forKey: "seer.temperature")
        #expect(s.temperature == 0.5)
    }
    @Test func temperatureReadSanitizesNonFiniteAndJunk() {
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        d.set(Double.nan, forKey: "seer.temperature")
        #expect(s.temperature == 0.2)
        d.set("hot", forKey: "seer.temperature")
        #expect(s.temperature == 0.2)
    }
    @Test func maxTokensDefaults() {
        #expect(AppSettings(defaults: freshDefaults()).maxTokens == 24)
    }
    @Test func maxTokensRoundTrips() {
        let s = AppSettings(defaults: freshDefaults())
        s.maxTokens = 32
        #expect(s.maxTokens == 32)
    }
    @Test func maxTokensReadClampsHandEdited() {
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        d.set(-3, forKey: "seer.maxTokens")
        #expect(s.maxTokens == 8)
        d.set(10_000, forKey: "seer.maxTokens")
        #expect(s.maxTokens == 48)
    }
    @Test func maxTokensReadCollapsesJunkTypeToLowerBound() {
        // integer(forKey:) parses what it can and yields 0 for junk, which clamps to the
        // lower bound — different from temperature's junk→default contract, deliberately.
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        d.set("lots", forKey: "seer.maxTokens")
        #expect(s.maxTokens == 8)
    }
    @Test func maxTokensReadStaysInRangeForAbsurdMagnitudes() {
        // NSNumber's double→integer conversion is architecture-dependent for out-of-range
        // values, so assert containment, not an exact value (trap-free is the contract).
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        d.set(1e19, forKey: "seer.maxTokens")
        #expect(AppSettings.maxTokensRange.contains(s.maxTokens))
        d.set(-1e19, forKey: "seer.maxTokens")
        #expect(AppSettings.maxTokensRange.contains(s.maxTokens))
    }
    @Test func tuningRangesExposedForUI() {
        #expect(AppSettings.temperatureRange == 0.2...0.5)
        #expect(AppSettings.maxTokensRange == 8...48)
    }
    // MARK: Ghost-text font settings (Phase 11)
    @Test func fontNameDefaultsToNilSystem() {
        #expect(AppSettings(defaults: freshDefaults()).fontName == nil)
    }
    @Test func fontNameRoundTrips() {
        let s = AppSettings(defaults: freshDefaults())
        s.fontName = "Menlo-Regular"
        #expect(s.fontName == "Menlo-Regular")
    }
    @Test func fontNameBlankOrNilCollapsesToNil() {
        let s = AppSettings(defaults: freshDefaults())
        s.fontName = "   "
        #expect(s.fontName == nil)
        s.fontName = "Menlo-Regular"
        s.fontName = nil
        #expect(s.fontName == nil)
    }
    @Test func fontNamePaddedValueRoundTripsUntrimmed() {
        // Deliberate: trim is only an emptiness check, matching OverlayFont.resolve's
        // preserve-raw semantics; a bad name degrades gracefully to the system font.
        let s = AppSettings(defaults: freshDefaults())
        s.fontName = "  Menlo  "
        #expect(s.fontName == "  Menlo  ")
    }
    @Test func fontSizeDefaults() {
        #expect(AppSettings(defaults: freshDefaults()).fontSize == 13)
    }
    @Test func fontSizeRoundTrips() {
        let s = AppSettings(defaults: freshDefaults())
        s.fontSize = 15
        #expect(s.fontSize == 15)
    }
    @Test func fontSizeReadClampsHandEdited() {
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        d.set(1.0, forKey: "seer.fontSize")
        #expect(s.fontSize == 6)
        d.set(500.0, forKey: "seer.fontSize")
        #expect(s.fontSize == 96)
        d.set(Double.nan, forKey: "seer.fontSize")
        #expect(s.fontSize == 13)
    }
    @Test func fontSizeReadCollapsesJunkTypeToDefault() {
        let d = freshDefaults()
        let s = AppSettings(defaults: d)
        d.set("big", forKey: "seer.fontSize")
        #expect(s.fontSize == 13)
    }
    @Test func fontBoundsMatchOverlayFontAuthority() {
        // Drift guard: AppSettings mirrors OverlayFont's constants instead of importing
        // SeerOverlay; this test is the tripwire if either side ever changes.
        #expect(AppSettings.fontSizeRange == OverlayFont.minSize...OverlayFont.maxSize)
        #expect(AppSettings.defaultFontSize == OverlayFont.defaultSize)
        #expect(OverlayFont.resolve(FontDescriptorInput(name: nil, size: AppSettings.fontSizeRange.lowerBound)).size
            == AppSettings.fontSizeRange.lowerBound)
        #expect(OverlayFont.resolve(FontDescriptorInput(name: nil, size: AppSettings.fontSizeRange.upperBound)).size
            == AppSettings.fontSizeRange.upperBound)
    }
}
