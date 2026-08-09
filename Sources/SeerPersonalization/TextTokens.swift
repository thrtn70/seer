/// Shared tokenizer for the derivation code. Words are lowercased runs of letters,
/// apostrophes, and hyphens — everything else is a separator, which structurally excludes
/// ChatML markers ("<|…") from ever entering a phrase or count.
enum TextTokens {
    static func words(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch == "'" || ch == "-" {
                current.append(ch)
            } else if !current.isEmpty {
                emit(current, into: &out); current = ""
            }
        }
        if !current.isEmpty { emit(current, into: &out) }
        return out
    }

    /// Strip leading/trailing apostrophes and hyphens (interior ones are kept) and append only
    /// if a letter run survives. A token stripped to empty was pure punctuation ("--", "''",
    /// "-"), which must never become a word — otherwise edge/bare punctuation would leak into
    /// the derived n-gram phrase table.
    private static func emit(_ token: String, into out: inout [String]) {
        var s = Substring(token)
        while let first = s.first, first == "'" || first == "-" { s = s.dropFirst() }
        while let last = s.last, last == "'" || last == "-" { s = s.dropLast() }
        if !s.isEmpty { out.append(String(s)) }
    }

    /// Sentence split on ./!/?/newline; blank segments dropped. A text with no terminator
    /// is one sentence.
    static func sentences(_ text: String) -> [String] {
        text.split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
