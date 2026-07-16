import llama
import os
import SeerModel

/// In-process streaming inference engine backed by llama.cpp + Metal (b9763).
///
/// Replaces the Phase 0 `llama-server` subprocess: tokenize, decode, sample, and
/// token rendering all run in-process. llama.cpp is NOT thread-safe, so every llama
/// call is confined to one dedicated serial `DispatchQueue`.
public final class LlamaCppEngine: InferenceEngine, @unchecked Sendable {
    public let kind: EngineKind = .llamaCpp

    /// Serial confinement for ALL llama.cpp calls (model is not thread-safe).
    private let queue = DispatchQueue(label: "app.seer.llama")
    private let model: LlamaModel
    let cache: KVCacheStore
    private let imEndToken: Int32?

    public init(modelPath: String) throws {
        self.model = try LlamaModel(modelPath: modelPath)
        self.cache = KVCacheStore(model: model)
        self.imEndToken = model.specialTokenID("<|im_end|>")
    }

    public var isAvailable: Bool { true }

    /// A read-only snapshot of the KV-cache Part B (stable-prefix snapshot/restore) state.
    public struct SnapshotStats: Sendable {
        /// Whether the init-time self-test trusts sequence-state restore on this context.
        public let enabled: Bool
        /// Snapshots actually stored in the LRU so far.
        public let captures: Int
        /// Successful restores (`llama_state_seq_set_data`) so far.
        public let restores: Int
    }

    /// Read the Part B snapshot counters on the serial queue.
    ///
    /// MUST be called from OUTSIDE the serial queue (it uses `queue.sync`) — e.g. from the
    /// bench's main thread between streams. Calling it from within a queued work item
    /// (a stream closure) would deadlock.
    public func snapshotStats() -> SnapshotStats {
        queue.sync {
            SnapshotStats(
                enabled: cache.snapshotEnabled,
                captures: cache.snapshotCaptures,
                restores: cache.snapshotRestores
            )
        }
    }

    /// Synchronously free llama.cpp/Metal resources on the serial queue.
    ///
    /// Call before process `exit()` so the Metal residency set is drained before
    /// llama.cpp's atexit device destructor runs (otherwise it aborts on a stale set).
    /// Safe to call once; further llama calls after this are undefined.
    public func shutdown() {
        // MUST be called from OUTSIDE the serial queue. It uses queue.sync, so calling it from within a queued work item (e.g. the stream closure) would deadlock. Intended for app/bench teardown before process exit.
        queue.sync { self.model.close() }
    }

    /// Decode a 1-token batch to JIT the Metal kernels so the first real stream is fast.
    public func warmUp() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            // `self` is @unchecked Sendable; the serial queue is the safety boundary.
            queue.async {
                let model = self.model
                var tokens: [Int32] = [llama_vocab_bos(model.vocab)]
                _ = tokens.withUnsafeMutableBufferPointer { ptr in
                    llama_decode(model.context, llama_batch_get_one(ptr.baseAddress, Int32(ptr.count)))
                }
                let mem = llama_get_memory(model.context)
                llama_memory_seq_rm(mem, 0, -1, -1)
                cont.resume()
            }
        }
    }

    public func stream(prompt: PromptPayload, params: SamplingParams, cacheKey: PrefixCacheKey?)
        -> AsyncThrowingStream<String, Error>
    {
        AsyncThrowingStream { cont in
            // The continuation has no `isCancelled`; track it explicitly.
            let cancellation = CancellationFlag()
            cont.onTermination = { _ in cancellation.cancel() }

            // `self` is @unchecked Sendable; the serial queue is the safety boundary.
            queue.async {
                let model = self.model
                let cache = self.cache
                do {
                    let eos = llama_vocab_eos(model.vocab)
                    let imEnd = self.imEndToken
                    // Cancellation is checked per-token at the loop top below. A cancel signalled during this prefill completes the full prefill before stopping (onTermination still cancels the stream). Task 7's incremental prefill narrows this window.
                    try cache.prepare(prompt: prompt, cacheKey: cacheKey)
                    let sampler = Sampler(params: params)

                    var assembler = UTF8PieceAssembler()
                    var produced = 0
                    let limit = max(0, params.maxTokens)
                    while produced < limit {
                        if cancellation.isCancelled { break }

                        let token = sampler.sample(context: model.context)
                        if token == eos || (imEnd != nil && token == imEnd!) {
                            let tail = assembler.flush()
                            if !tail.isEmpty { cont.yield(tail) }
                            break
                        }

                        let text = assembler.push(model.pieceBytes(token))
                        if !text.isEmpty { cont.yield(text) }
                        produced += 1

                        // The final yielded token is intentionally NOT appendDecoded (its logits would never be sampled). Consequence: the last yielded token is NOT committed to the KV cache, so KVCacheStore.tokenized / nPast exclude it. Task 7's prefix-reuse diff MUST account for this — do not assume every yielded token is in the cache.
                        if produced >= limit {
                            let tail = assembler.flush()
                            if !tail.isEmpty { cont.yield(tail) }
                            break
                        }
                        try cache.appendDecoded(token: token)
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
        }
    }
}

/// Minimal thread-safe cancellation flag for the streaming loop.
private final class CancellationFlag: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var cancelled = false

    var isCancelled: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return cancelled
    }

    func cancel() {
        os_unfair_lock_lock(&lock)
        cancelled = true
        os_unfair_lock_unlock(&lock)
    }
}
