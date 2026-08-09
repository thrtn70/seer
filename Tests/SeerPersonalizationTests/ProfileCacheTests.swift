import Testing
import SeerModel
@testable import SeerPersonalization

private func snap(version: UInt64) -> ProfileSnapshot {
    ProfileSnapshot(version: version, totalSamples: Int(version), global: nil, apps: [:],
                    overrides: .neutral)
}

@Suite struct ProfileCacheTests {
    @Test @MainActor func startsEmpty() {
        #expect(ProfileCache().snapshot == nil)
    }
    @Test @MainActor func publishesNewerVersions() {
        let cache = ProfileCache()
        cache.publish(snap(version: 1))
        cache.publish(snap(version: 2))
        #expect(cache.snapshot?.version == 2)
    }
    @Test @MainActor func rejectsStaleAndDuplicateVersions() {
        // Out-of-order delivery across the actor→main hops: v2 lands first, v1 must lose.
        let cache = ProfileCache()
        cache.publish(snap(version: 2))
        cache.publish(snap(version: 1))
        #expect(cache.snapshot?.version == 2)
        cache.publish(snap(version: 2))
        #expect(cache.snapshot?.version == 2)
    }
    @Test @MainActor func sameVersionKeepsTheFirstEvenIfContentDiffers() {
        // The guard is `>` not `>=`: a later same-version publish must not overwrite. The
        // duplicate test above uses identical content, so it can't tell `>` from `>=` — this
        // uses distinct content at the same version to pin the strict inequality.
        let cache = ProfileCache()
        cache.publish(ProfileSnapshot(version: 5, totalSamples: 100, global: nil, apps: [:],
                                      overrides: .neutral))
        cache.publish(ProfileSnapshot(version: 5, totalSamples: 999, global: nil, apps: [:],
                                      overrides: .neutral))
        #expect(cache.snapshot?.totalSamples == 100)   // first wins
    }
}
