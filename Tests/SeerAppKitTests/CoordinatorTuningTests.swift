import Testing
import Foundation
import SeerModel
@testable import SeerAppKit

/// Pins the AppSettings → CoordinatorTuning mapping — the gate the hand-maintained replay in
/// AgentDelegate.startCoordinator() never had. A persisted key that fails to reach the tuning
/// now fails here, instead of silently not applying until the user opens Settings.
///
/// The whole-struct `==` assertions are deliberate: adding a field to CoordinatorTuning breaks
/// both `init(_ s: AppSettings)` (must assign it) and the expected values below (must supply
/// it), so the compiler walks you to every place a new tunable has to be wired.
@Suite struct CoordinatorTuningTests {
    private func freshDefaults() -> UserDefaults {
        let name = "seer.test.\(UInt64.random(in: 0...(.max)))"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func freshSettingsMapToShippedDefaults() {
        #expect(CoordinatorTuning(AppSettings(defaults: freshDefaults()))
            == CoordinatorTuning(enabled: true,
                                 pausedBundles: [],
                                 sampling: SamplingParams(temperature: 0.2, topK: 40, topP: 0.9, maxTokens: 24),
                                 autoTemperature: false,
                                 fontName: nil,
                                 fontSize: 13))
    }

    @Test func everyPersistedKeyReachesTheTuning() {
        let s = AppSettings(defaults: freshDefaults())
        s.enabled = false
        s.pausedBundles = ["com.apple.TextEdit", "com.foo.bar"]
        s.temperature = 0.45
        s.maxTokens = 32
        s.fontName = "Menlo-Regular"
        s.fontSize = 15
        s.autoTemperature = true
        #expect(CoordinatorTuning(s)
            == CoordinatorTuning(enabled: false,
                                 pausedBundles: ["com.apple.TextEdit", "com.foo.bar"],
                                 sampling: SamplingParams(temperature: 0.45, topK: 40, topP: 0.9, maxTokens: 32),
                                 autoTemperature: true,
                                 fontName: "Menlo-Regular",
                                 fontSize: 15))
    }

    @Test func handEditedValuesArriveSanitized() {
        // `defaults write` is a supported surface: the mapping reads through AppSettings'
        // sanitizing getters, so junk is already clamped by the time it reaches the coordinator.
        let d = freshDefaults()
        d.set(9.0, forKey: "seer.temperature")
        d.set(10_000, forKey: "seer.maxTokens")
        d.set(500.0, forKey: "seer.fontSize")
        d.set("   ", forKey: "seer.fontName")
        let t = CoordinatorTuning(AppSettings(defaults: d))
        #expect(t.sampling.temperature == 0.5)
        #expect(t.sampling.maxTokens == 48)
        #expect(t.fontSize == 96)
        #expect(t.fontName == nil)
    }

    @Test func nonTunableSamplingFieldsKeepShippedDefaults() {
        // topK/topP have no Settings control and no AppSettings key; pin that the mapping
        // leaves SamplingParams' shipped defaults alone rather than drifting them.
        let s = AppSettings(defaults: freshDefaults())
        s.temperature = 0.5
        s.maxTokens = 8
        let t = CoordinatorTuning(s)
        #expect(t.sampling.topK == 40)
        #expect(t.sampling.topP == 0.9)
    }
}
