/// Deterministic, dependency-free hashing for byte-stable cache keys.
/// FNV-1a 64-bit — NOT Swift's `Hasher`/`hashValue` (those are per-process randomized).
public enum Hashing {
    public static func fnv1a64<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        var hash: UInt64 = 0xcbf29ce484222325
        for b in bytes {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
