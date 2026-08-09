import CryptoKit
import Foundation
import SeerModel

/// Owns the profile + all I/O, off the hot path (§3.3 G9). `record` is synchronous inside
/// the actor up to (and including) version assignment and persist — no suspension point —
/// so records serialize fully; only the MainActor publish hop is async, and ProfileCache's
/// monotonic guard resolves any delivery misordering. Key resolution and the vault load run
/// lazily on first use (inside the actor, so a Keychain prompt can never block the UI), and
/// records always load the existing vault BEFORE writing, so an early accept can't wipe the
/// on-disk history. Quit may lose ≤1 in-flight sample — accepted (§7.2 amendment).
public actor StyleProfileStore {
    public typealias Publish = @MainActor @Sendable (ProfileSnapshot) -> Void

    private let vault: PersonalizationVault?
    private let keyProvider: any KeyProviding
    private let now: @Sendable () -> Date
    private let publish: Publish
    private var key: SymmetricKey?
    private var loaded = false
    private var profile: StyleProfile = .empty
    private var version: UInt64 = 0
    private var overrides: ToneOverrides
    private var didLogPersistFailure = false

    public init(vault: PersonalizationVault?,
                keyProvider: any KeyProviding,
                now: @escaping @Sendable () -> Date = { Date() },
                overrides: ToneOverrides,   // no default: forgetting the startup replay is a compile error
                publish: @escaping Publish) {
        self.vault = vault
        self.keyProvider = keyProvider
        self.now = now
        self.overrides = overrides
        self.publish = publish
    }

    public func loadAndPublish() async {
        loadIfNeeded()
        version += 1
        let snap = ProfileSnapshot.build(from: profile, now: now(), version: version,
                                         overrides: overrides)
        await MainActor.run { [publish] in publish(snap) }
    }

    /// Live-apply the user's tone pins (§7.7). Not persisted here — AppSettings owns them;
    /// startup passes them via init. No-op (no version bump) for an unchanged value.
    public func setOverrides(_ o: ToneOverrides) async {
        loadIfNeeded()
        guard o != overrides else { return }
        overrides = o
        version += 1
        let snap = ProfileSnapshot.build(from: profile, now: now(), version: version,
                                         overrides: overrides)
        await MainActor.run { [publish] in publish(snap) }
    }

    /// §7.7 per-app reset: forgets one app's corpus; pins are preserved (user preferences).
    /// No-op for an unknown bundle (no bump, no publish, no write). loadIfNeeded() FIRST —
    /// a write before the vault load would persist a partial profile over the on-disk history.
    public func resetApp(_ bundleID: String) async {
        loadIfNeeded()
        guard profile.apps[bundleID] != nil else { return }
        profile.apps[bundleID] = nil
        version += 1
        let snap = ProfileSnapshot.build(from: profile, now: now(), version: version,
                                         overrides: overrides)
        persist()
        await MainActor.run { [publish] in publish(snap) }
    }

    /// §7.7 global reset — the privacy escape hatch. Persists the empty profile and removes
    /// the vault's `.corrupt`/`.tmp` siblings so no decryptable history outlives it. Always
    /// publishes (even from empty): the click deserves a confirmed fresh snapshot.
    public func resetAll() async {
        loadIfNeeded()
        profile = .empty
        version += 1
        let snap = ProfileSnapshot.build(from: profile, now: now(), version: version,
                                         overrides: overrides)
        persist()
        vault?.removeSiblings()
        await MainActor.run { [publish] in publish(snap) }
    }

    public func record(_ sample: AcceptedSample) async {
        loadIfNeeded()
        let reduced = ProfileReducer.reduce(profile, sample: sample)
        guard reduced != profile else { return }        // secure/blank drop: no write, no publish
        profile = reduced
        version += 1                                    // assigned before any suspension point
        let snap = ProfileSnapshot.build(from: profile, now: now(), version: version,
                                         overrides: overrides)
        persist()
        await MainActor.run { [publish] in publish(snap) }
    }

    /// Read-only §7.8 export of the CURRENT corpus + pins. Never publishes and never bumps
    /// the version — exporting must not perturb the cache or the coordinator's pin.
    public func exportPayload(includeRawText: Bool) throws -> Data {
        loadIfNeeded()
        let stamp = now()   // one sample: decay weights and exportedAt must agree
        let snap = ProfileSnapshot.build(from: profile, now: stamp, version: version,
                                         overrides: overrides)
        return try ProfileExport.json(profile: profile, snapshot: snap, overrides: overrides,
                                      includeRawText: includeRawText, now: stamp)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        key = keyProvider.loadOrCreateKey()
        guard let vault, let key else { return }        // memory-only session
        if case .profile(let stored) = vault.load(key: key) { profile = stored }
    }

    private func persist() {
        guard let vault, let key else { return }        // memory-only session
        do {
            try vault.save(profile, key: key)
        } catch {
            if !didLogPersistFailure {
                didLogPersistFailure = true
                FileHandle.standardError.write(Data(
                    "[seer] personalization persist failed: \(error)\n".utf8))
            }
        }
    }
}
