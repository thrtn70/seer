public enum WordTokenizer {
    /// Splits text into chunks where each chunk is a run of non-space characters
    /// plus any spaces that immediately follow it. The final chunk has no trailing
    /// space unless the input ended in one. Joining the chunks reproduces the input.
    public static func wordChunks(_ s: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        var sawNonSpaceSinceLastFlush = false

        for ch in s {
            if ch == " " {
                current.append(ch)
            } else {
                if sawNonSpaceSinceLastFlush, current.hasSuffix(" ") {
                    chunks.append(current)
                    current = ""
                    sawNonSpaceSinceLastFlush = false
                }
                current.append(ch)
                sawNonSpaceSinceLastFlush = true
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
