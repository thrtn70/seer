import llama
import SeerModel

/// Builds and owns a llama.cpp sampler chain (b9763) derived from `SamplingParams`.
///
/// NOT thread-safe — every method must run on the engine's serial queue, since the
/// chain reads the context's logits and is mutated by sampling.
///
/// Chain order matches llama.cpp's documented convention: top-k → top-p → temp → dist.
/// A fixed seed keeps the smoke run deterministic.
final class Sampler {
    private let chain: UnsafeMutablePointer<llama_sampler>

    /// Default seed for reproducible sampling (overridable for tests).
    static let defaultSeed: UInt32 = 0xC0FFEE

    init(params: SamplingParams, seed: UInt32 = Sampler.defaultSeed) {
        let chainParams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(chainParams) else {
            fatalError("llama_sampler_chain_init returned nil")
        }
        self.chain = chain

        // top-k → top-p → temp → dist. The chain takes ownership of each sub-sampler.
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(Int32(params.topK)))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(Float(params.topP), 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(params.temperature)))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(seed))
    }

    /// Samples one token from the logits of the last decoded position (`idx = -1`).
    func sample(context: OpaquePointer) -> Int32 {
        llama_sampler_sample(chain, context, -1)
    }

    deinit {
        // Frees the chain and every sub-sampler it owns.
        llama_sampler_free(chain)
    }
}
