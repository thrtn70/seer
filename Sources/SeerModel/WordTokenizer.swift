/// Splits text into chunks where each chunk is a run of non-space characters plus any spaces
/// that immediately follow it. Joining the chunks reproduces the input exactly.
/// Used for Tab=next-word (removeFirst) and ⇧Tab=whole-line (joined).
public enum WordTokenizer {
    public static func wordChunks(_ s: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        var sawNonSpaceSinceLastFlush = false
        for ch in s {
            if ch == " " {
                current.append(ch)
            } else {
                if sawNonSpaceSinceLastFlush, current.hasSuffix(" ") {
                    chunks.append(current); current = ""; sawNonSpaceSinceLastFlush = false
                }
                current.append(ch); sawNonSpaceSinceLastFlush = true
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
