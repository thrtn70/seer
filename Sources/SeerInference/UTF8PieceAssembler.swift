/// Reassembles UTF-8 codepoints from a stream of byte chunks (llama.cpp token pieces),
/// so a multibyte codepoint split across tokens is emitted once whole — never as U+FFFD.
/// Per-stream, single-threaded (lives on the engine's serial queue).
struct UTF8PieceAssembler {
    private var buffer: [UInt8] = []

    /// Appends `bytes`, returns the text for all newly-complete codepoints (may be "").
    mutating func push(_ bytes: [UInt8]) -> String {
        buffer.append(contentsOf: bytes)
        let split = completePrefixEnd()
        guard split > 0 else { return "" }
        let complete = Array(buffer[0..<split])
        buffer.removeFirst(split)
        return String(decoding: complete, as: UTF8.self)
    }

    /// Flushes any remaining (possibly incomplete) bytes at end of stream, best-effort.
    mutating func flush() -> String {
        guard !buffer.isEmpty else { return "" }
        let s = String(decoding: buffer, as: UTF8.self)  // incomplete tail → U+FFFD, deterministic
        buffer.removeAll()
        return s
    }

    /// Index in `buffer` immediately after the last fully-present codepoint.
    ///
    /// Walk lead bytes to determine expected codepoint length:
    ///   - 0x00–0x7F (ASCII): L = 1
    ///   - 0xC0–0xDF (2-byte lead): L = 2
    ///   - 0xE0–0xEF (3-byte lead): L = 3
    ///   - 0xF0–0xF7 (4-byte lead): L = 4
    ///   - Stray continuation 0x80–0xBF or invalid 0xF8+: L = 1 (anti-stall safeguard)
    ///
    /// If `i + L <= buffer.count`, the codepoint is fully present; advance and continue.
    /// Otherwise the codepoint is incomplete; stop and return `i`.
    private func completePrefixEnd() -> Int {
        var i = 0
        while i < buffer.count {
            let b = buffer[i]
            let length: Int
            switch b {
            case 0x00...0x7F:
                length = 1
            case 0xC0...0xDF:
                length = 2
            case 0xE0...0xEF:
                length = 3
            case 0xF0...0xF7:
                length = 4
            default:
                // Stray continuation byte (0x80–0xBF) or invalid lead (0xF8+).
                // Treat as a single-byte unit so it cannot stall the stream.
                length = 1
            }
            if i + length <= buffer.count {
                i += length
            } else {
                break
            }
        }
        return i
    }
}
