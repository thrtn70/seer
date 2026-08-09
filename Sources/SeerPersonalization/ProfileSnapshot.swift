import Foundation
import SeerModel

/// Immutable, Sendable derivation of the profile — what the hot path reads (§3.3 G9).
/// Built deterministically: apps iterated in sorted-key order so floating-point accumulation
/// order (and therefore every derived byte) is a pure function of content, not of dictionary
/// insertion history.
public struct ProfileSnapshot: Sendable, Equatable {
    public let version: UInt64
    public let totalSamples: Int
    public let global: ToneScores?               // DERIVED global (no pins) — the UI's "learned" view
    public let apps: [String: AppSnapshot]       // AppSnapshot.tone stays derived for the same reason
    public let overrides: ToneOverrides          // §7.7 manual pins, applied at read time
    public init(version: UInt64, totalSamples: Int, global: ToneScores?,
                apps: [String: AppSnapshot], overrides: ToneOverrides) {
        self.version = version; self.totalSamples = totalSamples
        self.global = global; self.apps = apps; self.overrides = overrides
    }

    /// §7.6 ladder + §7.7 pins: per-app derived tone (≥50) else global (≥20), then pinned
    /// axes replace derived values per axis. Pins never ACTIVATE a tone: base nil ⇒ nil, so
    /// below thresholds the prompt stays byte-identical to the unpersonalized scaffold.
    public func tone(for bundleID: String) -> ToneScores? {
        merged(apps[bundleID]?.tone ?? global)
    }
    /// The global tone with pins applied — what the tone sliders and the auto-temperature
    /// display hint show once active.
    public var effectiveGlobal: ToneScores? { merged(global) }
    private func merged(_ base: ToneScores?) -> ToneScores? {
        guard let base else { return nil }
        return ToneScores(formality: overrides.formality ?? base.formality,
                          warmth: overrides.warmth ?? base.warmth,
                          brevity: overrides.brevity ?? base.brevity)
    }

    public static func build(from profile: StyleProfile, now: Date, version: UInt64,
                             overrides: ToneOverrides) -> ProfileSnapshot {
        let sortedApps = profile.apps.sorted { $0.key < $1.key }
        var appSnaps: [String: AppSnapshot] = [:]
        var allWeighted: [WeightedText] = []
        var total = 0
        for (bundle, app) in sortedApps {
            let weighted: [WeightedText] = app.recents.map {
                (text: $0.completion,
                 weight: Decay.weight(ageDays: now.timeIntervalSince($0.timestamp) / 86_400))
            }
            total += app.recents.count
            allWeighted.append(contentsOf: weighted)
            let tone = app.recents.count >= ProfileThresholds.appOverride
                ? ToneDerivation.scores(from: weighted) : nil
            appSnaps[bundle] = AppSnapshot(sampleCount: app.recents.count, tone: tone,
                                           phrases: PhraseExtractor.topPhrases(from: weighted))
        }
        let global = total >= ProfileThresholds.globalActivation
            ? ToneDerivation.scores(from: allWeighted) : nil
        return ProfileSnapshot(version: version, totalSamples: total, global: global,
                               apps: appSnaps, overrides: overrides)
    }
}

public struct AppSnapshot: Sendable, Equatable {
    public let sampleCount: Int
    public let tone: ToneScores?                 // nil below ProfileThresholds.appOverride
    public let phrases: [String]                 // deterministic top-K
    public init(sampleCount: Int, tone: ToneScores?, phrases: [String]) {
        self.sampleCount = sampleCount; self.tone = tone; self.phrases = phrases
    }
}
