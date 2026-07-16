import llama
import Foundation
import SeerModel

/// Owns the KV-cache lifecycle for a generation run (b9763).
///
/// Task 7: incremental decode with prefix reuse. On each `prepare`, the new prompt is
/// diffed against the tokens currently materialized in the KV cache; the shared prefix
/// is kept, everything past it is dropped via `llama_memory_seq_rm`, and only the fresh
/// suffix is decoded. This append-only fast path (decode ~1 token per keystroke) is what
/// delivers warm sub-100 ms time-to-first-token.
///
/// Secondary: a CPU-side LRU of sequence-0 KV snapshots keyed by `cacheKey` lets a later
/// `prepare` restore a previously-decoded stable prefix instead of re-decoding it — when
/// the underlying llama.cpp context supports reliable state restore (see `snapshotEnabled`).
///
/// NOT thread-safe — every method touches llama.cpp context state and MUST run on the
/// engine's serial queue.
final class KVCacheStore {
    private let model: LlamaModel

    /// The prompt tokens produced by the most recent `prepare`. Mirrors the latest
    /// prepared prompt (the interface promise); callers diff against this conceptually.
    private(set) var tokenized: [Int32] = []

    /// Number of positions currently committed to the KV cache (prompt + decoded).
    ///
    /// Note: the engine may yield a token without a following appendDecoded (it skips the
    /// final token), so tokenized / nPast can lag the yielded output by one token.
    private(set) var nPast: Int32 = 0

    /// The EXACT tokens currently materialized in the KV cache for sequence 0. This is the
    /// reuse anchor: it grows by one on every `appendDecoded`, so after a stream it equals
    /// prompt + appended generated tokens. The next `prepare` diffs against THIS (not
    /// `tokenized`) so the `seq_rm` correctly clears any stale generated tail.
    private var cachedTokens: [Int32] = []

    private let sequenceID: Int32 = 0

    // MARK: - Part B: stable-prefix snapshot LRU

    /// One captured sequence-0 KV state plus the prefix tokens it represents.
    private struct Snapshot {
        let prefixTokens: [Int32]
        let data: Data
    }

    /// LRU cap for prefix snapshots. Small: only a handful of distinct prefixes are live.
    private static let snapshotCapacity = 3

    /// `cacheKey` → captured stable-prefix KV state. Capped at `snapshotCapacity`.
    private var snapshots: [PrefixCacheKey: Snapshot] = [:]
    /// Most-recently-used-last ordering for `snapshots` eviction.
    private var snapshotLRU: [PrefixCacheKey] = []

    /// Whether sequence-state restore is trusted on this context. Disabled by default:
    /// GPU-offload KV state restore is unreliable (llama.cpp #2422); snapshot reuse is
    /// disabled on Metal contexts, and the prefix is re-decoded instead. The flag is set
    /// once by a self-test at init. Revisit with a CPU-side prefix context in a later phase.
    let snapshotEnabled: Bool

    /// Observability for Part B (read off the engine's serial queue via `snapshotStats()`).
    /// `snapshotRestores` counts successful `llama_state_seq_set_data` restores;
    /// `snapshotCaptures` counts snapshots actually stored in the LRU.
    private(set) var snapshotRestores = 0
    private(set) var snapshotCaptures = 0

    init(model: LlamaModel) {
        self.model = model
        self.snapshotEnabled = KVCacheStore.probeStateRestore(model: model)
    }

    /// Incremental prefill: keep the KV positions shared with the previous run, drop the
    /// rest with `seq_rm`, and decode only the fresh suffix.
    func prepare(prompt: PromptPayload, cacheKey: PrefixCacheKey?) throws {
        let newTokens = try tokenize(prompt.fullText, addSpecial: true, parseSpecial: prompt.parseSpecial)
        guard !newTokens.isEmpty else {
            throw EngineError.backend("tokenize produced no tokens")
        }
        guard newTokens.count <= Int(llama_n_ctx(model.context)) else {
            throw EngineError.contextOverflow
        }

        // Try a stable-prefix snapshot restore first (Part B). On success, this sets the
        // KV cache to exactly the prefix tokens; the volatile tail is then decoded by the
        // common suffix-decode path below. On failure / when disabled it is a no-op and we
        // fall through to the plain prefix-diff path (Part A).
        if let restoredPrefix = tryRestoreSnapshot(prompt: prompt, cacheKey: cacheKey, newTokens: newTokens) {
            cachedTokens = restoredPrefix
            nPast = Int32(restoredPrefix.count)
        }

        // Part A: longest common prefix between what's cached and the new prompt.
        var keep = TokenPrefix.commonLength(cachedTokens, newTokens)

        // Edge case: if the new prompt is a prefix of (or identical to) what's cached, the
        // last prompt position would have no fresh logits to sample from. Re-decode at
        // least the final token so position -1 has logits. Guard keep >= 0.
        if keep == newTokens.count {
            keep = max(0, newTokens.count - 1)
        }

        // Drop every cached position from `keep` onward. This clears BOTH a diverged
        // behind-the-caret suffix AND any stale generated tokens left from a previous
        // stream. p1 < 0 means [keep, inf).
        //
        // The return value is `false` when a partial (non-contiguous) sequence cannot be
        // removed — which would leave the cache ending at the wrong position and silently
        // cause the warm (reuse) decode to diverge from a cold prefill. Make that loud.
        let mem = llama_get_memory(model.context)
        let seqRmOK = llama_memory_seq_rm(mem, sequenceID, Int32(keep), -1)
        guard seqRmOK else {
            throw EngineError.backend("seq_rm failed at keep=\(keep)")
        }
        nPast = Int32(keep)

        // Decode the fresh suffix as one batch from position `keep`. Positions auto-track
        // off the sequence's memory, which now ends at `keep` after the seq_rm.
        let suffix = Array(newTokens[keep...])
        if !suffix.isEmpty {
            try decode(tokens: suffix)
        }

        cachedTokens = newTokens
        nPast = Int32(newTokens.count)
        tokenized = newTokens

        // Capture a stable-prefix snapshot for future reuse (Part B). No-op when disabled.
        captureSnapshotIfNeeded(prompt: prompt, cacheKey: cacheKey, newTokens: newTokens)
    }

    /// Decode one sampled token at the next position, advancing `nPast` and the cache anchor.
    func appendDecoded(token: Int32) throws {
        guard nPast < Int32(llama_n_ctx(model.context)) else {
            throw EngineError.contextOverflow
        }
        try decode(tokens: [token])
        nPast += 1
        cachedTokens.append(token)
    }

    // MARK: - Part B: snapshot capture / restore

    /// Tokens of the stable prefix (with BOS/specials), used as the snapshot anchor.
    private func prefixTokens(of prompt: PromptPayload) throws -> [Int32] {
        guard !prompt.stablePrefix.isEmpty else { return [] }
        return try tokenize(prompt.stablePrefix, addSpecial: true, parseSpecial: prompt.parseSpecial)
    }

    /// If a snapshot for `cacheKey` exists AND its prefix still tokenizes identically AND
    /// the new prompt actually starts with that prefix, restore sequence-0 state from it.
    /// Returns the restored prefix tokens on success, else nil (caller re-decodes).
    private func tryRestoreSnapshot(
        prompt: PromptPayload, cacheKey: PrefixCacheKey?, newTokens: [Int32]
    ) -> [Int32]? {
        guard snapshotEnabled, let cacheKey, let snap = snapshots[cacheKey] else { return nil }

        // Guard: the new prompt must begin with exactly the snapshot's prefix tokens.
        guard snap.prefixTokens.count <= newTokens.count,
              TokenPrefix.commonLength(snap.prefixTokens, newTokens) == snap.prefixTokens.count
        else { return nil }

        let mem = llama_get_memory(model.context)
        llama_memory_seq_rm(mem, sequenceID, -1, -1)
        let read: size_t = snap.data.withUnsafeBytes { raw in
            llama_state_seq_set_data(
                model.context, raw.bindMemory(to: UInt8.self).baseAddress,
                snap.data.count, sequenceID
            )
        }
        guard read > 0 else {
            // Restore failed; leave the sequence cleared, caller decodes from scratch.
            cachedTokens = []
            nPast = 0
            return nil
        }
        touchLRU(cacheKey)
        snapshotRestores += 1
        return snap.prefixTokens
    }

    /// Largest count of stable-prefix tokens that are provably a TRUE prefix of the full
    /// combined tokenization. Tokenizing `stablePrefix` alone can split the seam token
    /// differently from `stablePrefix + context`, so the standalone prefix is not always a
    /// token-prefix of `newTokens`. We snapshot only the tokens that genuinely match, which
    /// keeps restore byte-for-byte correct. Returns 0 when nothing is safely shareable.
    private func safePrefixLength(prompt: PromptPayload, newTokens: [Int32]) -> Int {
        guard let standalone = try? prefixTokens(of: prompt), !standalone.isEmpty else { return 0 }
        return min(standalone.count, TokenPrefix.commonLength(standalone, newTokens))
    }

    /// After the stable prefix is materialized in the cache, capture its sequence-0 state
    /// over the safe shared-prefix span. Captures once per `cacheKey`/prefix-token-set.
    private func captureSnapshotIfNeeded(
        prompt: PromptPayload, cacheKey: PrefixCacheKey?, newTokens: [Int32]
    ) {
        guard snapshotEnabled, let cacheKey else { return }
        let keep = safePrefixLength(prompt: prompt, newTokens: newTokens)
        guard keep > 0, keep < newTokens.count else { return }
        let prefix = Array(newTokens[0..<keep])
        if let existing = snapshots[cacheKey], existing.prefixTokens == prefix {
            touchLRU(cacheKey)
            return
        }

        // The cache currently holds `newTokens` (prefix + volatile tail). Trim to the
        // prefix span, snapshot sequence-0, then re-decode the tail so the cache again
        // matches `newTokens` for streaming.
        let mem = llama_get_memory(model.context)
        llama_memory_seq_rm(mem, sequenceID, Int32(keep), -1)

        let size = llama_state_seq_get_size(model.context, sequenceID)
        guard size > 0 else {
            restoreTailAfterCapture(prefix: prefix, fullTokens: newTokens)
            return
        }
        var buffer = Data(count: size)
        let written: size_t = buffer.withUnsafeMutableBytes { raw in
            llama_state_seq_get_data(
                model.context, raw.bindMemory(to: UInt8.self).baseAddress, size, sequenceID
            )
        }
        if written > 0 {
            if written < size { buffer.removeSubrange(Int(written)..<buffer.count) }
            insertSnapshot(cacheKey, Snapshot(prefixTokens: prefix, data: buffer))
        }

        restoreTailAfterCapture(prefix: prefix, fullTokens: newTokens)
    }

    /// Re-decode the volatile tail after a capture trimmed the cache to the prefix.
    private func restoreTailAfterCapture(prefix: [Int32], fullTokens: [Int32]) {
        nPast = Int32(prefix.count)
        let tail = Array(fullTokens[prefix.count...])
        if !tail.isEmpty {
            // Best-effort; a failure here only loses the speedup, never correctness, since
            // the next prepare re-diffs. Decode errors are swallowed deliberately.
            try? decode(tokens: tail)
        }
        cachedTokens = fullTokens
        nPast = Int32(fullTokens.count)
    }

    private func insertSnapshot(_ key: PrefixCacheKey, _ snap: Snapshot) {
        snapshots[key] = snap
        snapshotCaptures += 1
        touchLRU(key)
        while snapshotLRU.count > KVCacheStore.snapshotCapacity {
            let evicted = snapshotLRU.removeFirst()
            snapshots[evicted] = nil
        }
    }

    private func touchLRU(_ key: PrefixCacheKey) {
        if let idx = snapshotLRU.firstIndex(of: key) { snapshotLRU.remove(at: idx) }
        snapshotLRU.append(key)
    }

    /// One-time self-test: capture sequence-0 state, clear it, restore, and decode a token.
    /// Returns true only if the round-trip succeeds. On GPU-offloaded Metal contexts this
    /// is expected to be unreliable (llama.cpp #2422) — a failure here disables Part B and
    /// the prefix is re-decoded instead. Leaves the sequence cleared for the first prepare.
    private static func probeStateRestore(model: LlamaModel) -> Bool {
        let ctx = model.context
        let mem = llama_get_memory(ctx)
        llama_memory_seq_rm(mem, 0, -1, -1)

        var probe: [Int32] = [llama_vocab_bos(model.vocab)]
        let decodeRC = probe.withUnsafeMutableBufferPointer { ptr -> Int32 in
            llama_decode(ctx, llama_batch_get_one(ptr.baseAddress, Int32(ptr.count)))
        }
        guard decodeRC == 0 else {
            llama_memory_seq_rm(mem, 0, -1, -1)
            return false
        }

        let size = llama_state_seq_get_size(ctx, 0)
        guard size > 0 else {
            llama_memory_seq_rm(mem, 0, -1, -1)
            return false
        }
        var buffer = [UInt8](repeating: 0, count: size)
        let written = buffer.withUnsafeMutableBufferPointer { raw in
            llama_state_seq_get_data(ctx, raw.baseAddress, size, 0)
        }
        // Clear and attempt to restore.
        llama_memory_seq_rm(mem, 0, -1, -1)
        let read = buffer.withUnsafeBufferPointer { raw in
            llama_state_seq_set_data(ctx, raw.baseAddress, Int(written), 0)
        }
        // Leave the probe state cleared for the first real prepare.
        llama_memory_seq_rm(mem, 0, -1, -1)
        return written > 0 && read > 0
    }

    // MARK: - Private

    private func tokenize(_ text: String, addSpecial: Bool, parseSpecial: Bool) throws -> [Int32] {
        let utf8Count = Int32(text.utf8.count)
        // Upper bound: never more tokens than bytes (+ a slot for BOS).
        let capacity = Int(utf8Count) + 1
        var tokens = [Int32](repeating: 0, count: capacity)

        let n = text.withCString { cText in
            llama_tokenize(
                model.vocab,
                cText,
                utf8Count,
                &tokens,
                Int32(capacity),
                addSpecial,
                parseSpecial
            )
        }
        guard n >= 0 else {
            throw EngineError.backend("llama_tokenize failed (\(n))")
        }
        return Array(tokens.prefix(Int(n)))
    }

    private func decode(tokens: [Int32]) throws {
        var mutable = tokens
        let rc = mutable.withUnsafeMutableBufferPointer { ptr -> Int32 in
            let batch = llama_batch_get_one(ptr.baseAddress, Int32(ptr.count))
            return llama_decode(model.context, batch)
        }
        switch rc {
        case 0:
            return
        case 1:
            // No KV slot — context is full.
            throw EngineError.contextOverflow
        default:
            throw EngineError.backend("llama_decode failed (\(rc))")
        }
    }
}
