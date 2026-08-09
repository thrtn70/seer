import Testing
import Foundation
import SeerModel
@testable import SeerPersonalization

private func profileWith(counts: [String: Int], completion: String = "thanks for the update",
                         t: TimeInterval = 0) -> StyleProfile {
    var apps: [String: AppProfile] = [:]
    for (bundle, n) in counts {
        apps[bundle] = AppProfile(recents: (0..<n).map { i in
            StoredAcceptance(completion: completion, beforeCaret: "b",
                             timestamp: Date(timeIntervalSince1970: t + Double(i)))
        })
    }
    return StyleProfile(apps: apps)
}
private let now = Date(timeIntervalSince1970: 1_000)

@Suite struct ProfileSnapshotTests {
    @Test func belowGlobalThresholdHasNilGlobalTone() {
        let snap = ProfileSnapshot.build(
            from: profileWith(counts: ["a": ProfileThresholds.globalActivation - 1]),
            now: now, version: 1, overrides: .neutral)
        #expect(snap.global == nil)
        #expect(snap.tone(for: "a") == nil)
        #expect(snap.totalSamples == ProfileThresholds.globalActivation - 1)
    }
    @Test func atGlobalThresholdGlobalToneActivates() {
        let snap = ProfileSnapshot.build(
            from: profileWith(counts: ["a": ProfileThresholds.globalActivation]),
            now: now, version: 1, overrides: .neutral)
        #expect(snap.global != nil)
        #expect(snap.tone(for: "a") == snap.global)              // below app override → global
        #expect(snap.tone(for: "unknown.app") == snap.global)    // unknown app → global too
    }
    @Test func globalCountsAcrossApps() {
        let half = ProfileThresholds.globalActivation / 2
        let snap = ProfileSnapshot.build(from: profileWith(counts: ["a": half, "b": half]),
                                         now: now, version: 1, overrides: .neutral)
        #expect(snap.global != nil)
    }
    @Test func appOverrideActivatesAtFifty() {
        let snap = ProfileSnapshot.build(
            from: profileWith(counts: ["a": ProfileThresholds.appOverride]),
            now: now, version: 1, overrides: .neutral)
        #expect(snap.apps["a"]?.tone != nil)
        #expect(snap.tone(for: "a") == snap.apps["a"]?.tone)
    }
    @Test func appToneDiffersFromGlobalWhenCorporaDiffer() {
        // App "verbose" (50 long samples) overrides; global blends both corpora.
        var apps: [String: AppProfile] = [:]
        apps["brief"] = AppProfile(recents: (0..<30).map { i in
            StoredAcceptance(completion: "ok. thanks. done.", beforeCaret: "b",
                             timestamp: Date(timeIntervalSince1970: Double(i)))
        })
        apps["verbose"] = AppProfile(recents: (0..<50).map { i in
            StoredAcceptance(completion: "i wanted to follow up regarding the discussion we had "
                + "earlier this week about the quarterly planning process and considerations",
                beforeCaret: "b", timestamp: Date(timeIntervalSince1970: Double(i)))
        })
        let snap = ProfileSnapshot.build(from: StyleProfile(apps: apps), now: now, version: 1, overrides: .neutral)
        let verboseTone = snap.tone(for: "verbose")
        let briefTone = snap.tone(for: "brief")       // < 50 samples → falls to global blend
        #expect(verboseTone != nil && briefTone != nil)
        #expect(verboseTone!.brevity < briefTone!.brevity)
    }
    @Test func phrasesAreDerivedPerApp() {
        let snap = ProfileSnapshot.build(from: profileWith(counts: ["a": 30]), now: now, version: 1, overrides: .neutral)
        #expect(snap.apps["a"]?.phrases.contains("thanks for") == true)
        #expect(snap.apps["a"]?.phrases.isEmpty == false)
    }
    @Test func buildIsDeterministicAcrossDictionaryInsertionOrder() {
        // Two profiles with identical content but different dictionary insertion histories
        // must produce equal snapshots (FP sums included) — the descriptor's byte stability
        // stands on this.
        // 12 apps × 2 samples = 24 ≥ globalActivation, so the GLOBAL tone is computed too —
        // that's the floating-point accumulation whose order this test pins.
        var apps1: [String: AppProfile] = [:]
        var apps2: [String: AppProfile] = [:]
        let names = (0..<12).map { "app.number\($0)" }
        func recents(_ name: String) -> [StoredAcceptance] {
            [StoredAcceptance(completion: "thanks for the help with \(name)", beforeCaret: "b",
                              timestamp: Date(timeIntervalSince1970: 0)),
             StoredAcceptance(completion: "will do, no worries at all", beforeCaret: "b",
                              timestamp: Date(timeIntervalSince1970: 10))]
        }
        for name in names { apps1[name] = AppProfile(recents: recents(name)) }
        for name in names.reversed() { apps2[name] = AppProfile(recents: recents(name)) }
        let s1 = ProfileSnapshot.build(from: StyleProfile(apps: apps1), now: now, version: 7, overrides: .neutral)
        let s2 = ProfileSnapshot.build(from: StyleProfile(apps: apps2), now: now, version: 7, overrides: .neutral)
        #expect(s1 == s2)
    }
    @Test func versionIsCarriedThrough() {
        let snap = ProfileSnapshot.build(from: .empty, now: now, version: 42, overrides: .neutral)
        #expect(snap.version == 42)
        #expect(snap.totalSamples == 0)
        #expect(snap.global == nil)
    }
    @Test func appOverrideBelowThresholdHasNilAppTone() {
        // Symmetry with the global threshold's -1 test: 49 samples must NOT activate the app
        // override. Without this, a `>= appOverride - 1` mutation (activating one sample early)
        // passes the whole suite because the exact-50 test still activates.
        let snap = ProfileSnapshot.build(
            from: profileWith(counts: ["a": ProfileThresholds.appOverride - 1]),
            now: now, version: 1, overrides: .neutral)
        #expect(snap.apps["a"]?.tone == nil)
    }

    // MARK: - §7.7 manual pins (Phase 12.x)
    @Test func pinnedAxisWinsOverGlobalOthersStayDerived() throws {
        let profile = profileWith(counts: ["a": ProfileThresholds.globalActivation])
        let derived = try #require(ProfileSnapshot.build(from: profile, now: now, version: 1,
                                                         overrides: .neutral).tone(for: "a"))
        let pinned = try #require(ProfileSnapshot.build(
            from: profile, now: now, version: 1,
            overrides: ToneOverrides(formality: 0.9, warmth: nil, brevity: nil)).tone(for: "a"))
        #expect(pinned.formality == 0.9)
        #expect(pinned.warmth == derived.warmth)
        #expect(pinned.brevity == derived.brevity)
    }
    @Test func pinnedAxisWinsOverPerAppDerivedTone() throws {
        // Locked decision: a pin applies everywhere — including over an ACTIVE ≥50 app tone.
        let profile = profileWith(counts: ["a": ProfileThresholds.appOverride])
        let derived = try #require(ProfileSnapshot.build(from: profile, now: now, version: 1,
                                                         overrides: .neutral).tone(for: "a"))
        let pinned = try #require(ProfileSnapshot.build(
            from: profile, now: now, version: 1,
            overrides: ToneOverrides(formality: nil, warmth: nil, brevity: 0.1)).tone(for: "a"))
        #expect(pinned.brevity == 0.1)
        #expect(pinned.formality == derived.formality)
    }
    @Test func allAxesPinnedReplaceEverything() throws {
        let profile = profileWith(counts: ["a": ProfileThresholds.globalActivation])
        let t = try #require(ProfileSnapshot.build(
            from: profile, now: now, version: 1,
            overrides: ToneOverrides(formality: 0.1, warmth: 0.2, brevity: 0.3)).tone(for: "a"))
        #expect(t == ToneScores(formality: 0.1, warmth: 0.2, brevity: 0.3))
    }
    @Test func overridesNeverActivateANilTone() {
        let snap = ProfileSnapshot.build(
            from: profileWith(counts: ["a": ProfileThresholds.globalActivation - 1]),
            now: now, version: 1,
            overrides: ToneOverrides(formality: 0.9, warmth: 0.9, brevity: 0.9))
        #expect(snap.tone(for: "a") == nil)
        #expect(snap.effectiveGlobal == nil)
    }
    @Test func neutralOverridesPreserveTheDerivedLadder() {
        let snap = ProfileSnapshot.build(from: profileWith(counts: ["a": ProfileThresholds.appOverride]),
                                         now: now, version: 1, overrides: .neutral)
        #expect(snap.tone(for: "a") == snap.apps["a"]?.tone)
        #expect(snap.tone(for: "unknown") == snap.global)
        #expect(snap.effectiveGlobal == snap.global)
    }
    @Test func perAppToneImpliesGlobalTone() {
        // The invariant the merge stands on (appOverride 50 ≥ globalActivation 20, and
        // totalSamples ≥ any per-app count): app tone active ⟹ global active. There is no
        // state where tone(for:) is non-nil while effectiveGlobal is nil.
        let snap = ProfileSnapshot.build(from: profileWith(counts: ["a": ProfileThresholds.appOverride]),
                                         now: now, version: 1, overrides: .neutral)
        #expect(snap.apps["a"]?.tone != nil)
        #expect(snap.global != nil)
    }
    @Test func effectiveGlobalMergesPins() throws {
        let snap = ProfileSnapshot.build(from: profileWith(counts: ["a": ProfileThresholds.globalActivation]),
                                         now: now, version: 1,
                                         overrides: ToneOverrides(formality: nil, warmth: 1.0, brevity: nil))
        let eff = try #require(snap.effectiveGlobal)
        let raw = try #require(snap.global)
        #expect(eff.warmth == 1.0)
        #expect(eff.formality == raw.formality)
    }
    @Test func buildIsDeterministicAcrossInsertionOrderWithOverridesSet() {
        var apps1: [String: AppProfile] = [:]
        var apps2: [String: AppProfile] = [:]
        let names = (0..<12).map { "app.number\($0)" }
        func recents(_ name: String) -> [StoredAcceptance] {
            [StoredAcceptance(completion: "thanks for the help with \(name)", beforeCaret: "b",
                              timestamp: Date(timeIntervalSince1970: 0)),
             StoredAcceptance(completion: "will do, no worries at all", beforeCaret: "b",
                              timestamp: Date(timeIntervalSince1970: 10))]
        }
        for name in names { apps1[name] = AppProfile(recents: recents(name)) }
        for name in names.reversed() { apps2[name] = AppProfile(recents: recents(name)) }
        let ov = ToneOverrides(formality: 0.25, warmth: nil, brevity: 0.75)
        let s1 = ProfileSnapshot.build(from: StyleProfile(apps: apps1), now: now, version: 7, overrides: ov)
        let s2 = ProfileSnapshot.build(from: StyleProfile(apps: apps2), now: now, version: 7, overrides: ov)
        #expect(s1 == s2)
        #expect(s1.tone(for: "app.number0") == s2.tone(for: "app.number0"))
    }
}
