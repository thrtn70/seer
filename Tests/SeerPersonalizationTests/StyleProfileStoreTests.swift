import Testing
import Foundation
import CryptoKit
import SeerModel
@testable import SeerPersonalization

private func tempVault() -> PersonalizationVault {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("seer-store-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return PersonalizationVault(fileURL: dir.appendingPathComponent("personalization.db"))
}
private let fixedKey = SymmetricKey(size: .bits256)
private let fixedNow = Date(timeIntervalSince1970: 1_000)

private func sample(_ completion: String, bundle: String = "com.apple.TextEdit",
                    subrole: String? = nil) -> AcceptedSample {
    AcceptedSample(bundleID: bundle, focusedSubrole: subrole, completion: completion,
                   beforeCaret: "b", timestamp: fixedNow)
}

@Suite struct StyleProfileStoreTests {
    @Test @MainActor func recordPublishesAndPersists() async {
        let vault = tempVault()
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: vault, keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral, publish: { cache.publish($0) })
        await store.record(sample("thanks for the update"))
        #expect(cache.snapshot?.totalSamples == 1)
        #expect(cache.snapshot?.version == 1)
        // Persisted per record: a second store over the same vault sees it.
        guard case .profile(let onDisk) = vault.load(key: fixedKey) else {
            Issue.record("expected a persisted profile"); return
        }
        #expect(onDisk.apps["com.apple.TextEdit"]?.recents.count == 1)
    }
    @Test @MainActor func versionsAreMonotonicAcrossRecords() async {
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral, publish: { cache.publish($0) })
        await store.record(sample("one two"))
        await store.record(sample("three four"))
        #expect(cache.snapshot?.version == 2)
        #expect(cache.snapshot?.totalSamples == 2)
    }
    @Test @MainActor func interleavedRecordsNeverRegressTheCache() async {
        // The reentrancy race (design F8): concurrent records may deliver out of order across
        // the MainActor hop; the version guard means the LATEST content always wins.
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral, publish: { cache.publish($0) })
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask { await store.record(sample("sample number \(i)")) }
            }
        }
        #expect(cache.snapshot?.version == 20)
        #expect(cache.snapshot?.totalSamples == 20)
    }
    @Test @MainActor func recordLoadsExistingVaultBeforeWriting() async {
        // Startup race (design F8): an early accept must not wipe the on-disk history by
        // persisting a 1-sample profile before the load ran.
        let vault = tempVault()
        try! vault.save(ProfileReducer.reduce(.empty, sample: sample("historic sample")), key: fixedKey)
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: vault, keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral, publish: { cache.publish($0) })
        await store.record(sample("fresh sample"))     // no loadAndPublish() first — on purpose
        #expect(cache.snapshot?.totalSamples == 2)
    }
    @Test @MainActor func loadAndPublishSurfacesTheStoredProfile() async {
        let vault = tempVault()
        try! vault.save(ProfileReducer.reduce(.empty, sample: sample("historic sample")), key: fixedKey)
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: vault, keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral, publish: { cache.publish($0) })
        await store.loadAndPublish()
        #expect(cache.snapshot?.totalSamples == 1)
        #expect(cache.snapshot?.version == 1)
    }
    @Test @MainActor func nilKeyRunsMemoryOnly() async {
        let vault = tempVault()
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: vault, keyProvider: InMemoryKeyProvider(key: nil),
                                      now: { fixedNow }, overrides: .neutral, publish: { cache.publish($0) })
        await store.record(sample("learned but not persisted"))
        #expect(cache.snapshot?.totalSamples == 1)                       // still learns
        #expect(!FileManager.default.fileExists(atPath: vault.fileURL.path))  // never persists
    }
    @Test @MainActor func secureSampleIsDroppedEntirely() async {
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral, publish: { cache.publish($0) })
        await store.record(sample("hunter2", subrole: "AXSecureTextField"))
        #expect(cache.snapshot == nil)      // no publish for a dropped sample
    }

    // MARK: - §7.7 mutators (Phase 12.x)
    @Test @MainActor func setOverridesPublishesMergedSnapshot() async {
        // RED against Task 3's `.neutral` placeholder: a store that ignores its overrides
        // state publishes an unmerged snapshot and this fails.
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        for i in 0..<ProfileThresholds.globalActivation {
            await store.record(sample("sample number \(i)"))
        }
        #expect(cache.snapshot?.effectiveGlobal != nil)
        await store.setOverrides(ToneOverrides(formality: nil, warmth: nil, brevity: 0.05))
        #expect(cache.snapshot?.effectiveGlobal?.brevity == 0.05)
        #expect(cache.snapshot?.version == UInt64(ProfileThresholds.globalActivation) + 1)
    }
    @Test @MainActor func initOverridesShapeTheFirstPublishedSnapshot() async {
        // Startup replay: pins passed at init are live from the first load, no setter call.
        let vault = tempVault()
        var seeded = StyleProfile.empty
        for i in 0..<ProfileThresholds.globalActivation {
            seeded = ProfileReducer.reduce(seeded, sample: sample("historic sample \(i)"))
        }
        try! vault.save(seeded, key: fixedKey)
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: vault, keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow },
                                      overrides: ToneOverrides(formality: 0.9, warmth: nil, brevity: nil),
                                      publish: { cache.publish($0) })
        await store.loadAndPublish()
        #expect(cache.snapshot?.effectiveGlobal?.formality == 0.9)
    }
    @Test @MainActor func setOverridesSameValueDoesNotRepublish() async {
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        await store.record(sample("one"))
        await store.setOverrides(.neutral)
        #expect(cache.snapshot?.version == 1)
    }
    @Test @MainActor func resetAppAsFirstOperationPreservesOtherAppsOnDisk() async {
        // THE data-loss guard: a fresh store whose resetApp skips loadIfNeeded() would
        // persist `.empty` over the entire on-disk history.
        let vault = tempVault()
        var seeded = StyleProfile.empty
        seeded = ProfileReducer.reduce(seeded, sample: sample("keep me", bundle: "app.keep"))
        seeded = ProfileReducer.reduce(seeded, sample: sample("drop me", bundle: "app.drop"))
        try! vault.save(seeded, key: fixedKey)
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: vault, keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        await store.resetApp("app.drop")               // first operation — no prior load
        guard case .profile(let onDisk) = vault.load(key: fixedKey) else {
            Issue.record("expected a persisted profile"); return
        }
        #expect(onDisk.apps["app.keep"]?.recents.count == 1)
        #expect(onDisk.apps["app.drop"] == nil)
        #expect(cache.snapshot?.totalSamples == 1)
    }
    @Test @MainActor func resetAppUnknownBundleIsANoOp() async {
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        await store.record(sample("one"))
        await store.resetApp("not.a.known.bundle")
        #expect(cache.snapshot?.version == 1)          // no bump, no publish, no write
    }
    @Test @MainActor func resetAppDroppingTotalBelowThresholdDeactivatesGlobalTone() async {
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        for i in 0..<ProfileThresholds.globalActivation { await store.record(sample("s \(i)")) }
        #expect(cache.snapshot?.global != nil)
        await store.resetApp("com.apple.TextEdit")
        #expect(cache.snapshot?.global == nil)
        #expect(cache.snapshot?.totalSamples == 0)
    }
    @Test @MainActor func resetAllEmptiesDiskAndCacheAndRemovesSiblings() async {
        let vault = tempVault()
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: vault, keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        await store.record(sample("about to be forgotten"))
        // Plant the artifacts a real vault can leave behind (§7.8 amendment).
        let dir = vault.fileURL.deletingLastPathComponent()
        let corrupt = dir.appendingPathComponent(vault.fileURL.lastPathComponent + ".corrupt")
        let tmp = dir.appendingPathComponent(vault.fileURL.lastPathComponent + ".tmp")
        try! Data("old ciphertext".utf8).write(to: corrupt)
        try! Data("partial write".utf8).write(to: tmp)
        await store.resetAll()
        #expect(cache.snapshot?.totalSamples == 0)
        #expect(cache.snapshot?.version == 2)
        guard case .profile(let onDisk) = vault.load(key: fixedKey) else {
            Issue.record("expected a persisted empty profile"); return
        }
        #expect(onDisk == .empty)
        #expect(!FileManager.default.fileExists(atPath: corrupt.path))
        #expect(!FileManager.default.fileExists(atPath: tmp.path))
    }
    @Test @MainActor func memoryOnlyResetStillPublishes() async {
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: nil),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        await store.record(sample("x"))
        await store.resetAll()
        #expect(cache.snapshot?.totalSamples == 0)
    }
    @Test @MainActor func exportPayloadReadsDiskWithoutPriorLoad() async throws {
        let vault = tempVault()
        try! vault.save(ProfileReducer.reduce(.empty, sample: sample("alpha bravo", bundle: "app.x")),
                        key: fixedKey)
        let store = StyleProfileStore(vault: vault, keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral, publish: { _ in })
        let text = String(decoding: try await store.exportPayload(includeRawText: true), as: UTF8.self)
        #expect(text.contains("alpha bravo"))
        #expect(text.contains("app.x"))
    }
    @Test @MainActor func exportPayloadNeverPublishes() async throws {
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        await store.record(sample("one"))
        _ = try await store.exportPayload(includeRawText: false)
        #expect(cache.snapshot?.version == 1)          // export is read-only
    }
    @Test @MainActor func resetAllAsFirstOperationOverwritesDiskHistory() async {
        // Mirror of THE data-loss guard, for the privacy escape hatch: without loadIfNeeded(),
        // a fresh store has no key, persist() silently no-ops, and the "deleted" history
        // resurrects on the next load.
        let vault = tempVault()
        try! vault.save(ProfileReducer.reduce(.empty, sample: sample("must not resurrect")), key: fixedKey)
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: vault, keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        await store.resetAll()                          // first operation — no prior load
        guard case .profile(let onDisk) = vault.load(key: fixedKey) else {
            Issue.record("expected a persisted empty profile"); return
        }
        #expect(onDisk == .empty)
        await store.record(sample("fresh start"))
        #expect(cache.snapshot?.totalSamples == 1)      // no resurrection
    }
    @Test @MainActor func pinsSurviveRecordAndResetAppPublishes() async {
        // Kills the `.neutral` mutant at record's and resetApp's build sites: the LAST
        // publish before each assertion comes from that mutator, and must still merge the
        // init pin. (resetAll's own publish is always empty ⇒ merged nil — its overrides
        // argument is an equivalent mutant, deliberately uncovered.)
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow },
                                      overrides: ToneOverrides(formality: 0.9, warmth: nil, brevity: nil),
                                      publish: { cache.publish($0) })
        for i in 0..<ProfileThresholds.globalActivation { await store.record(sample("a \(i)")) }
        await store.record(sample("extra", bundle: "app.other"))
        #expect(cache.snapshot?.effectiveGlobal?.formality == 0.9)      // record's publish merges
        await store.resetApp("app.other")
        #expect(cache.snapshot?.totalSamples == ProfileThresholds.globalActivation)
        #expect(cache.snapshot?.effectiveGlobal?.formality == 0.9)      // resetApp's publish merges
    }
    @Test @MainActor func setOverridesAsFirstOperationLoadsTheVault() async {
        var seeded = StyleProfile.empty
        for i in 0..<ProfileThresholds.globalActivation {
            seeded = ProfileReducer.reduce(seeded, sample: sample("historic \(i)"))
        }
        let vault = tempVault()
        try! vault.save(seeded, key: fixedKey)
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: vault, keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        await store.setOverrides(ToneOverrides(formality: nil, warmth: nil, brevity: 0.2))
        #expect(cache.snapshot?.totalSamples == ProfileThresholds.globalActivation)
        #expect(cache.snapshot?.effectiveGlobal?.brevity == 0.2)
    }
    @Test @MainActor func learningContinuesAfterResetAll() async {
        let cache = ProfileCache()
        let store = StyleProfileStore(vault: tempVault(), keyProvider: InMemoryKeyProvider(key: fixedKey),
                                      now: { fixedNow }, overrides: .neutral,
                                      publish: { cache.publish($0) })
        await store.record(sample("first life"))
        await store.resetAll()
        await store.record(sample("second life"))
        #expect(cache.snapshot?.totalSamples == 1)
        #expect(cache.snapshot?.version == 3)
    }
}
