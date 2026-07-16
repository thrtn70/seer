import Testing
@testable import SeerModel

@Suite struct PrefixCacheKeyTests {
    @Test func sameInputsSameKey() {
        let a = PrefixCacheKey(bundleID: "com.apple.mail", prefixHash: 42)
        let b = PrefixCacheKey(bundleID: "com.apple.mail", prefixHash: 42)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
    @Test func differsByBundle() {
        #expect(PrefixCacheKey(bundleID: "a", prefixHash: 1) != PrefixCacheKey(bundleID: "b", prefixHash: 1))
    }
    @Test func differsByHash() {
        #expect(PrefixCacheKey(bundleID: "a", prefixHash: 1) != PrefixCacheKey(bundleID: "a", prefixHash: 2))
    }

    // MARK: - Deterministic prefixHash derivation (FNV-1a 64-bit)

    @Test func derivedSamePrefixSameKey() {
        let prefix = "You are a helpful writing assistant.\nExample: Hello there!"
        let a = PrefixCacheKey(bundleID: "app.seer.bench", stablePrefix: prefix)
        let b = PrefixCacheKey(bundleID: "app.seer.bench", stablePrefix: prefix)
        #expect(a == b)
        #expect(a.prefixHash == b.prefixHash)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func derivedDifferentPrefixDifferentHash() {
        let a = PrefixCacheKey(bundleID: "app.seer.bench", stablePrefix: "alpha")
        let b = PrefixCacheKey(bundleID: "app.seer.bench", stablePrefix: "beta")
        #expect(a.prefixHash != b.prefixHash)
        #expect(a != b)
    }

    @Test func derivedIsDeterministic() {
        // Computed twice in-process — must match (proves no per-process randomization).
        let prefix = "Stable prefix that must hash identically every time."
        let first = PrefixCacheKey(bundleID: "x", stablePrefix: prefix).prefixHash
        let second = PrefixCacheKey(bundleID: "x", stablePrefix: prefix).prefixHash
        #expect(first == second)
    }

    @Test func derivedEmptyPrefixIsFNVOffsetBasis() {
        // Known FNV-1a 64-bit vector: empty input → the offset basis.
        #expect(PrefixCacheKey(bundleID: "x", stablePrefix: "").prefixHash == 0xcbf29ce484222325)
    }

    @Test func derivedKnownVectorA() {
        // Known FNV-1a 64-bit vector: "a" → 0xaf63dc4c8601ec8c.
        #expect(PrefixCacheKey(bundleID: "x", stablePrefix: "a").prefixHash == 0xaf63dc4c8601ec8c)
    }
}
