import Foundation

/// Corpus → tone axes (§7.4, minimal signal set). All formulas are fixed v1 heuristics with
/// pinned anchors; the tests assert monotonic behavior and clamping, not psychometric truth.
/// Deterministic: pure accumulation over the input array in order (callers pass ordered
/// corpora — see ProfileSnapshot.build).
public enum ToneDerivation {
    /// Words in ["the","and",…] are "function words" — high ratios read as conventional,
    /// structured prose (one weak formality signal alongside contraction rate).
    static let functionWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "at", "by", "for",
        "with", "from", "as", "that", "this", "these", "those", "is", "are", "was", "were",
        "be", "been", "it", "they", "we", "you", "i", "he", "she", "not", "do", "does",
        "did", "have", "has", "had",
    ]
    static let affectWords: Set<String> = [
        "thanks", "thank", "please", "great", "love", "happy", "glad", "wonderful",
        "awesome", "appreciate", "excited", "amazing", "nice", "good", "best", "hope",
        "fantastic", "cool", "perfect", "congrats", "congratulations", "welcome", "cheers",
    ]
    /// Brevity anchors: mean sentence length ≤4 words → 1.0; ≥24 → 0.0; linear between.
    static let briefMeanWords = 4.0
    static let verboseMeanWords = 24.0

    public static func scores(from corpus: [WeightedText]) -> ToneScores? {
        var wTokens = 0.0, wContractions = 0.0, wFunction = 0.0, wAffect = 0.0
        var wSentences = 0.0, wSentenceWords = 0.0, wExclaims = 0.0
        // Determinism: FP addition is non-associative, so accumulate in a canonical order fixed
        // by the corpus multiset, never the caller's presentation order — the derived axes (and
        // therefore the style descriptor / KV-cache prefix built from them) must be byte-stable.
        // Same guard as PhraseExtractor: drop invalid weights before sorting so NaN can't poison
        // the strict-weak-ordering.
        let ordered = corpus
            .filter { $0.weight > 0 && $0.weight.isFinite }
            .sorted { ($0.text, $0.weight) < ($1.text, $1.weight) }
        for entry in ordered {
            let words = TextTokens.words(entry.text)
            guard !words.isEmpty else { continue }
            let w = entry.weight
            wTokens += w * Double(words.count)
            wContractions += w * Double(words.filter { $0.contains("'") }.count)
            wFunction += w * Double(words.filter { functionWords.contains($0) }.count)
            wAffect += w * Double(words.filter { affectWords.contains($0) }.count)
            let sentences = TextTokens.sentences(entry.text)
            let sentenceCount = max(sentences.count, 1)
            wSentences += w * Double(sentenceCount)
            wSentenceWords += w * Double(words.count)
            wExclaims += w * Double(entry.text.filter { $0 == "!" }.count)
        }
        guard wTokens > 0, wSentences > 0 else { return nil }
        let contractionRate = wContractions / wTokens
        let functionRatio = wFunction / wTokens
        let affectRate = wAffect / wTokens
        let exclaimRate = wExclaims / wSentences
        let meanSentenceWords = wSentenceWords / wSentences
        let brevity = clamp01((verboseMeanWords - meanSentenceWords)
                              / (verboseMeanWords - briefMeanWords))
        let formality = clamp01(0.6 * (1 - min(contractionRate * 8, 1))
                                + 0.4 * min(functionRatio * 2.5, 1))
        let warmth = clamp01(0.5 * min(affectRate * 25, 1) + 0.5 * min(exclaimRate * 2, 1))
        return ToneScores(formality: formality, warmth: warmth, brevity: brevity)
    }

    private static func clamp01(_ v: Double) -> Double {
        guard v.isFinite else { return 0.5 }
        return min(max(v, 0), 1)
    }
}
