import SeerInference

extension InferenceEngine {
    /// Calls shutdown() on engines that have it (LlamaCppEngine); no-op otherwise (mocks).
    func shutdownIfPossible() { (self as? LlamaCppEngine)?.shutdown() }
}
