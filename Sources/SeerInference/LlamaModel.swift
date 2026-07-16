import llama
import Foundation

/// Owns the llama.cpp model + context lifecycle (b9763).
///
/// NOT thread-safe — llama.cpp's model/context state must be confined to a single
/// serial executor. Task 6 (`LlamaCppEngine`) enforces that confinement; this type
/// only manages allocation and teardown.
final class LlamaModel {
    let model: OpaquePointer
    let context: OpaquePointer
    let vocab: OpaquePointer

    /// Guards against double-free between `close()` and `deinit`.
    private var freed = false

    init(modelPath: String, nCtx: Int32 = 2048, nGpuLayers: Int32 = 99) throws {
        llama_backend_init()

        var mp = llama_model_default_params()
        mp.n_gpu_layers = nGpuLayers
        guard let m = llama_model_load_from_file(modelPath, mp) else {
            llama_backend_free()
            throw EngineError.backend("model load")
        }

        var cp = llama_context_default_params()
        cp.n_ctx = UInt32(nCtx)
        cp.n_batch = 512
        guard let c = llama_init_from_model(m, cp) else {
            llama_model_free(m)
            llama_backend_free()
            throw EngineError.backend("ctx init")
        }

        guard let v = llama_model_get_vocab(m) else {
            llama_free(c)
            llama_model_free(m)
            llama_backend_free()
            throw EngineError.backend("vocab")
        }

        self.model = m
        self.context = c
        self.vocab = v
    }

    /// Explicitly free the context, model, and backend.
    ///
    /// Idempotent. MUST run on the engine's serial queue. Call this BEFORE process
    /// `exit()`: it drains the Metal residency set so llama.cpp's global device
    /// destructor (run via atexit) does not trip `GGML_ASSERT(rsets->data count == 0)`.
    func close() {
        guard !freed else { return }
        freed = true
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    deinit {
        close()
    }

    /// The token id for a special control string (e.g. "<|im_end|>"), or nil if it does not
    /// tokenize to exactly one token. Uses parse_special so the control marker is recognized.
    func specialTokenID(_ text: String) -> Int32? {
        var tokens = [Int32](repeating: 0, count: 8)
        let n = text.withCString { c in
            llama_tokenize(vocab, c, Int32(text.utf8.count), &tokens, 8,
                           /*addSpecial*/ false, /*parseSpecial*/ true)
        }
        guard n == 1 else { return nil }
        return tokens[0]
    }

    /// Return the raw bytes of a single token's piece via `llama_token_to_piece`.
    ///
    /// MUST be called on the engine's serial queue (llama.cpp is not thread-safe).
    /// Handles the negative-return "buffer too small" case by resizing once.
    /// Returns raw bytes so callers can accumulate them with `UTF8PieceAssembler`
    /// and avoid U+FFFD on multibyte codepoints split across token boundaries.
    func pieceBytes(_ token: Int32) -> [UInt8] {
        var buf = [CChar](repeating: 0, count: 32)
        let n = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
        if n < 0 {
            // Negative return = required length; resize and retry.
            buf = [CChar](repeating: 0, count: Int(-n))
            let n2 = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
            guard n2 > 0 else { return [] }
            return Array(buf.prefix(Int(n2)).map { UInt8(bitPattern: $0) })
        }
        guard n > 0 else { return [] }
        return Array(buf.prefix(Int(n)).map { UInt8(bitPattern: $0) })
    }
}
