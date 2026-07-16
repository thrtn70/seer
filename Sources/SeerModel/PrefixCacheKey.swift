public struct PrefixCacheKey: Hashable, Sendable {
    public let bundleID: String
    public let prefixHash: UInt64
    public init(bundleID: String, prefixHash: UInt64) {
        self.bundleID = bundleID; self.prefixHash = prefixHash
    }

    /// Derive a deterministic key from the byte-stable prefix string.
    ///
    /// Uses FNV-1a (64-bit) over the prefix's UTF-8 bytes — NOT Swift's `Hasher`/
    /// `hashValue`, which is per-process randomized and would make the key unstable
    /// across runs (defeating cross-launch / cross-field KV-snapshot reuse).
    public init(bundleID: String, stablePrefix: String) {
        self.bundleID = bundleID
        self.prefixHash = Hashing.fnv1a64(stablePrefix.utf8)
    }
}
