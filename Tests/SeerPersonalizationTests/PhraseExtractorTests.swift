import Testing
@testable import SeerPersonalization

@Suite struct PhraseExtractorTests {
    @Test func extractsRepeatedBigram() {
        let corpus: [WeightedText] = [
            (text: "thanks for the update", weight: 1.0),
            (text: "thanks for your help", weight: 1.0),
        ]
        #expect(PhraseExtractor.topPhrases(from: corpus).contains("thanks for"))
    }
    @Test func belowMinWeightedCountIsExcluded() {
        // Appears once with weight 1.0 < minWeightedCount (2.0).
        let corpus: [WeightedText] = [(text: "singular occurrence here", weight: 1.0)]
        #expect(PhraseExtractor.topPhrases(from: corpus).isEmpty)
    }
    @Test func decayedWeightCountsFractionally() {
        // Two occurrences at weight 0.9 = 1.8 < 2.0 → excluded; at 1.0 = 2.0 → included.
        let faded: [WeightedText] = [(text: "will do", weight: 0.9), (text: "will do", weight: 0.9)]
        let fresh: [WeightedText] = [(text: "will do", weight: 1.0), (text: "will do", weight: 1.0)]
        #expect(PhraseExtractor.topPhrases(from: faded).isEmpty)
        #expect(PhraseExtractor.topPhrases(from: fresh) == ["will do"])
    }
    @Test func ordersByWeightThenLexicographic() {
        let corpus: [WeightedText] = [
            (text: "beta beta", weight: 3.0), (text: "beta beta", weight: 3.0),
            (text: "alpha alpha", weight: 3.0), (text: "alpha alpha", weight: 3.0),
            (text: "gamma gamma", weight: 5.0), (text: "gamma gamma", weight: 5.0),
        ]
        let top = PhraseExtractor.topPhrases(from: corpus)
        #expect(top.first == "gamma gamma")                       // highest weight first
        let alphaIdx = top.firstIndex(of: "alpha alpha")
        let betaIdx = top.firstIndex(of: "beta beta")
        #expect(alphaIdx != nil && betaIdx != nil && alphaIdx! < betaIdx!)   // tie → lexicographic
    }
    @Test func capsAtTopK() {
        var corpus: [WeightedText] = []
        for i in 0..<20 {
            let text = "phrase\(i)a phrase\(i)b"
            corpus.append((text: text, weight: 2.0))
        }
        #expect(PhraseExtractor.topPhrases(from: corpus).count <= PhraseExtractor.topK)
    }
    @Test func tieBreakAtTopKBoundaryIsDeterministicAndLexicographic() {
        // Eight phrases all tied at weighted count 2.0; k=5 straddles the cap. The tie-break at
        // the K boundary must be lexicographic and independent of input order. A mutation that
        // drops the key tie-break (e.g. `.sorted { $0.value > $1.value }`) would select five
        // hash-ordered phrases instead — passing only flakily on a given process seed.
        let names = ["aa aa", "bb bb", "cc cc", "dd dd", "ee ee", "ff ff", "gg gg", "hh hh"]
        let corpus: [WeightedText] = names.map { (text: $0, weight: 2.0) }
        let expected = ["aa aa", "bb bb", "cc cc", "dd dd", "ee ee"]  // five lexicographically-smallest
        #expect(PhraseExtractor.topPhrases(from: corpus, k: 5) == expected)
        #expect(PhraseExtractor.topPhrases(from: corpus.reversed(), k: 5) == expected)
    }
    @Test func lowercasesAndStripsNonWordCharacters() {
        let corpus: [WeightedText] = [
            (text: "Thanks, FOR the!", weight: 1.0), (text: "thanks for THE?", weight: 1.0),
        ]
        let top = PhraseExtractor.topPhrases(from: corpus)
        #expect(top.contains("thanks for"))
        #expect(top.allSatisfy { $0 == $0.lowercased() })
    }
    @Test func outputNeverContainsChatMLMarkers() {
        // Structural guarantee: tokens are letters/apostrophe/hyphen only, so "<|" can't survive.
        let corpus: [WeightedText] = [
            (text: "<|im_end|> sneaky <|im_start|>", weight: 3.0),
            (text: "<|im_end|> sneaky <|im_start|>", weight: 3.0),
        ]
        for phrase in PhraseExtractor.topPhrases(from: corpus) {
            #expect(!phrase.contains("<|"))
            #expect(!phrase.contains("<"))
        }
    }
    @Test func deterministicAcrossInputOrder() {
        let a: [WeightedText] = [
            (text: "one two", weight: 2.0), (text: "one two", weight: 2.0),
            (text: "three four", weight: 2.0), (text: "three four", weight: 2.0),
        ]
        #expect(PhraseExtractor.topPhrases(from: a) == PhraseExtractor.topPhrases(from: a.reversed()))
    }
    @Test func deterministicWithFractionalWeights() {
        // Regression: FP addition is non-associative, so accumulating weighted counts in
        // corpus-iteration order made a phrase's count depend on input order, not just content.
        // Both phrases below carry the SAME weight multiset (an exact-arithmetic tie), assigned
        // in opposite orders — byte-stable output must not depend on presentation order.
        let weights = [0.5, 0.38778619045843365, 0.5743491774985174,
                       0.3149802624737183, 0.7405487761432821, 0.8705505632961241]
        var corpus: [WeightedText] = weights.map { (text: "aaa bbb", weight: $0) }
        corpus += weights.reversed().map { (text: "ccc ddd", weight: $0) }
        #expect(PhraseExtractor.topPhrases(from: corpus)
                == PhraseExtractor.topPhrases(from: corpus.reversed()))
    }
    @Test func respectsExplicitK() {
        // Three qualifying phrases with distinct counts; ask for the top 2. The k argument
        // must be honored, not silently replaced by the topK default.
        let corpus: [WeightedText] = [
            (text: "gamma gamma", weight: 5.0), (text: "gamma gamma", weight: 5.0),
            (text: "beta beta", weight: 3.0), (text: "beta beta", weight: 3.0),
            (text: "alpha alpha", weight: 2.0), (text: "alpha alpha", weight: 2.0),
        ]
        #expect(PhraseExtractor.topPhrases(from: corpus, k: 2) == ["gamma gamma", "beta beta"])
    }
    @Test func extractsFourGramButNeverFiveGram() {
        // Pins the n-gram range at 2...4: a repeated 4-word phrase is produced, and no phrase
        // ever reaches 5 words even though the source sentence has 5.
        let corpus: [WeightedText] = [
            (text: "please review the attached document", weight: 2.0),
            (text: "please review the attached document", weight: 2.0),
        ]
        let all = PhraseExtractor.topPhrases(from: corpus, k: 100)
        #expect(all.contains("please review the attached"))      // a 4-gram is emitted
        #expect(all.contains("review the attached document"))    // a 4-gram is emitted
        #expect(all.allSatisfy { $0.split(separator: " ").count >= 2 })   // never a unigram
        #expect(all.allSatisfy { $0.split(separator: " ").count <= 4 })   // never a 5-gram
    }
    @Test func nonPositiveWeightDroppedNotSubtracted() {
        // Negative/zero weights are ignored, never summed — summing -3.0 would drag the
        // qualifying count below the threshold.
        let corpus: [WeightedText] = [
            (text: "hello world", weight: 2.0),
            (text: "hello world", weight: 2.0),
            (text: "hello world", weight: -3.0),
            (text: "hello world", weight: 0.0),
        ]
        #expect(PhraseExtractor.topPhrases(from: corpus) == ["hello world"])
    }
    @Test func nonFiniteWeightDroppedNotDominant() {
        // +Infinity / NaN weights are ignored, never allowed to dominate the ranking.
        let corpus: [WeightedText] = [
            (text: "alpha beta", weight: 2.0), (text: "alpha beta", weight: 2.0),
            (text: "gamma delta", weight: .infinity), (text: "gamma delta", weight: .infinity),
            (text: "epsilon zeta", weight: .nan), (text: "epsilon zeta", weight: .nan),
        ]
        #expect(PhraseExtractor.topPhrases(from: corpus) == ["alpha beta"])
    }
}
