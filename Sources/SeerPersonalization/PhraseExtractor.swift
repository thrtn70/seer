/// (text, decay weight) pair — the corpus unit every derivation function consumes.
public typealias WeightedText = (text: String, weight: Double)

/// Weighted word n-grams → deterministic top-K (§7.3 phrase table, derived not stored).
/// Total order: weighted count desc, then lexicographic — byte-stable output is load-bearing
/// (the descriptor built from it is the KV-cache prefix).
public enum PhraseExtractor {
    public static let ngramRange: ClosedRange<Int> = 2...4
    public static let minWeightedCount = 2.0
    public static let topK = 5

    public static func topPhrases(from corpus: [WeightedText], k: Int = topK) -> [String] {
        // Determinism: FP addition is non-associative, so the weighted count must be a pure
        // function of the corpus *multiset*, never its presentation order. Drop invalid weights
        // first (so NaN can't poison the sort's strict-weak-ordering), then accumulate in a
        // canonical (text, weight) order — the sorted sequence is uniquely fixed by the multiset,
        // giving byte-stable output regardless of how the caller assembled the corpus.
        let ordered = corpus
            .filter { $0.weight > 0 && $0.weight.isFinite }
            .sorted { ($0.text, $0.weight) < ($1.text, $1.weight) }
        var counts: [String: Double] = [:]
        for entry in ordered {
            let words = TextTokens.words(entry.text)
            for n in ngramRange where words.count >= n {
                for start in 0...(words.count - n) {
                    let phrase = words[start..<(start + n)].joined(separator: " ")
                    counts[phrase, default: 0] += entry.weight
                }
            }
        }
        return counts.filter { $0.value >= minWeightedCount }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }   // count desc, key asc
            .prefix(k)
            .map(\.key)
    }
}
