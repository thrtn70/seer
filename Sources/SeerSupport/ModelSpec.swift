import Foundation

/// The one description of the model Seer runs. Previously this filename was a bare literal in
/// three Swift call sites and three shell scripts with no shared constant; the checksum existed
/// nowhere at all, so nothing pinned the ~1 GB of bytes the app now downloads for itself.
///
/// `sha256` was computed over the vendored file AND cross-checked against the SHA256 HuggingFace
/// publishes for that LFS object — the two agree. `ModelSpecTests` asserts scripts/fetch-model.sh
/// still names the same URL and hash, so the shell and Swift halves cannot drift apart silently.
public enum ModelSpec {
    public static let filename = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
    public static let sourceURL = URL(string:
        "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!
    public static let sha256 = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
    /// Used only to render a total in the progress line before the server reports one.
    public static let expectedByteCount: Int64 = 1_117_320_736
}
