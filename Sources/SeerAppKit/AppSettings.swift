import Foundation
import SeerModel

/// Persisted app-layer settings (UserDefaults). Injectable suite for tests.
public struct AppSettings {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private enum Key {
        static let enabled = "seer.enabled"
        static let paused = "seer.pausedBundles"
        static let onboarded = "seer.onboardingComplete"
        static let statsDay = "seer.stats.dayKey"
        static let statsWords = "seer.stats.wordsAccepted"
        static let statsLatencySum = "seer.stats.latencySumMs"
        static let statsLatencyCount = "seer.stats.latencyCount"
        static let temperature = "seer.temperature"
        static let maxTokens = "seer.maxTokens"
        static let fontName = "seer.fontName"
        static let fontSize = "seer.fontSize"
        static let autoTemperature = "seer.autoTemperature"
        static let toneOverrideFormality = "seer.toneOverrideFormality"
        static let toneOverrideWarmth = "seer.toneOverrideWarmth"
        static let toneOverrideBrevity = "seer.toneOverrideBrevity"
    }
    public var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }   // default ON
        nonmutating set { defaults.set(newValue, forKey: Key.enabled) }
    }
    public var pausedBundles: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.paused) ?? []) }
        nonmutating set { defaults.set(Array(newValue).sorted(), forKey: Key.paused) }
    }
    public var onboardingComplete: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        nonmutating set { defaults.set(newValue, forKey: Key.onboarded) }
    }
    /// Bounds/defaults for the user-tunable generation knobs. Temperature is low and
    /// hard-bounded (design spec §7.4: predictable ghost text); the Settings UI sliders
    /// read these same constants. Reads sanitize hand-edited values (`defaults write`
    /// is a supported surface): out-of-range values clamp to the bound. Junk/non-finite
    /// collapse to the default for temperature; maxTokens parses what it can (junk reads
    /// as 0) and clamps to the bound.
    public static let temperatureRange: ClosedRange<Double> = 0.2...0.5
    public static let defaultTemperature = 0.2
    public static let maxTokensRange: ClosedRange<Int> = 8...48
    public static let defaultMaxTokens = 24
    public var temperature: Double {
        get {
            guard let raw = defaults.object(forKey: Key.temperature) as? Double, raw.isFinite
            else { return Self.defaultTemperature }
            return min(max(raw, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.temperature) }
    }
    public var maxTokens: Int {
        get {
            guard defaults.object(forKey: Key.maxTokens) != nil else { return Self.defaultMaxTokens }
            return min(max(defaults.integer(forKey: Key.maxTokens), Self.maxTokensRange.lowerBound),
                       Self.maxTokensRange.upperBound)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.maxTokens) }
    }
    /// "Auto (match my style)" (§7.4 as amended): when true, the coordinator derives
    /// temperature from the learned brevity tone; the manual temperature slider is ignored
    /// (but its value is preserved for when auto is switched back off). Default OFF.
    public var autoTemperature: Bool {
        get { defaults.object(forKey: Key.autoTemperature) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.autoTemperature) }
    }
    /// §7.7 (as amended): per-axis manual tone pins; nil = axis stays learned. Reads sanitize
    /// through ToneOverrides' own init (non-finite / out-of-range → nil), so there is exactly
    /// one sanitizer. NSNumber note: a Bool written under one of these keys bridges to
    /// 0.0/1.0 — in range, so it pins the axis; accepted precedent (temperature behaves the
    /// same under `defaults write -bool`).
    public var toneOverrides: ToneOverrides {
        get {
            ToneOverrides(formality: defaults.object(forKey: Key.toneOverrideFormality) as? Double,
                          warmth: defaults.object(forKey: Key.toneOverrideWarmth) as? Double,
                          brevity: defaults.object(forKey: Key.toneOverrideBrevity) as? Double)
        }
        nonmutating set {
            let pairs: [(String, Double?)] = [
                (Key.toneOverrideFormality, newValue.formality),
                (Key.toneOverrideWarmth, newValue.warmth),
                (Key.toneOverrideBrevity, newValue.brevity),
            ]
            for (key, value) in pairs {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
    }
    /// Ghost-text font. `fontName` nil ⇒ system font; blank writes collapse to nil.
    /// Size bounds mirror OverlayFont's (`resolve` stays the final authority; a drift-guard
    /// test asserts the constants agree). Reads sanitize hand-edited values.
    public static let fontSizeRange: ClosedRange<Double> = 6...96
    public static let defaultFontSize: Double = 13
    public var fontName: String? {
        get {
            guard let raw = defaults.string(forKey: Key.fontName),
                  !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return raw
        }
        nonmutating set {
            if let v = newValue, !v.trimmingCharacters(in: .whitespaces).isEmpty {
                defaults.set(v, forKey: Key.fontName)
            } else {
                defaults.removeObject(forKey: Key.fontName)
            }
        }
    }
    public var fontSize: Double {
        get {
            guard let raw = defaults.object(forKey: Key.fontSize) as? Double, raw.isFinite
            else { return Self.defaultFontSize }
            return min(max(raw, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.fontSize) }
    }
    /// Sanity caps for hand-edited stats values: a day can't contain more than a day of
    /// latency milliseconds, and seven-figure daily word/sample counts are physically
    /// impossible. Keeps downstream arithmetic and Int conversions trap-free.
    private enum StatsCap {
        static let count = 1_000_000
        static let latencySumMs = 86_400_000.0   // one day in ms
    }
    /// Persisted daily stats; nil = never recorded. Setting nil clears all four keys.
    /// Reads sanitize hand-edited values (negatives, non-finite, and absurd magnitudes collapse to safe bounds).
    public var dailyStats: DailyStats? {
        get {
            guard let day = defaults.string(forKey: Key.statsDay) else { return nil }
            // Single main-actor writer assumed (MenuController); the four keys are not written atomically.
            let rawSum = defaults.double(forKey: Key.statsLatencySum)
            return DailyStats(dayKey: day,
                              wordsAccepted: min(max(0, defaults.integer(forKey: Key.statsWords)), StatsCap.count),
                              latencySumMs: rawSum.isFinite ? min(max(0, rawSum), StatsCap.latencySumMs) : 0,
                              latencyCount: min(max(0, defaults.integer(forKey: Key.statsLatencyCount)), StatsCap.count))
        }
        nonmutating set {
            guard let v = newValue else {
                for key in [Key.statsDay, Key.statsWords, Key.statsLatencySum, Key.statsLatencyCount] {
                    defaults.removeObject(forKey: key)
                }
                return
            }
            defaults.set(v.dayKey, forKey: Key.statsDay)
            defaults.set(v.wordsAccepted, forKey: Key.statsWords)
            defaults.set(v.latencySumMs, forKey: Key.statsLatencySum)
            defaults.set(v.latencyCount, forKey: Key.statsLatencyCount)
        }
    }
}
