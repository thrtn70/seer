import Testing
@testable import SeerPersonalization

@Suite struct ToneDerivationTests {
    @Test func emptyCorpusIsNil() {
        #expect(ToneDerivation.scores(from: []) == nil)
        #expect(ToneDerivation.scores(from: [(text: "!!!", weight: 1.0)]) == nil)  // no word tokens
        #expect(ToneDerivation.scores(from: [(text: "hi there", weight: 0.0)]) == nil)  // zero weight
    }
    @Test func allAxesAreClamped01() throws {
        let t = try #require(ToneDerivation.scores(from: [
            (text: "Thanks so much!!! I really love it! Great work!", weight: 1.0),
        ]))
        for v in [t.formality, t.warmth, t.brevity] { #expect(v >= 0 && v <= 1) }
    }
    @Test func shortSentencesScoreBrieferThanLongOnes() throws {
        let brief = try #require(ToneDerivation.scores(from: [(text: "ok. will do. thanks.", weight: 1.0)]))
        let long = try #require(ToneDerivation.scores(from: [(text:
            "i wanted to follow up regarding the discussion we had earlier this week about the "
            + "quarterly planning process and the various considerations around it", weight: 1.0)]))
        #expect(brief.brevity > long.brevity)
        #expect(brief.brevity > 0.9)      // ≤4-word mean saturates
        #expect(long.brevity < 0.1)       // ≥24-word mean saturates
    }
    @Test func contractionsLowerFormality() throws {
        let casual = try #require(ToneDerivation.scores(from: [
            (text: "don't think it'll work, can't say I'd try", weight: 1.0)]))
        let formal = try #require(ToneDerivation.scores(from: [
            (text: "do not think it will work, cannot say I would try", weight: 1.0)]))
        #expect(casual.formality < formal.formality)
    }
    @Test func affectWordsAndExclamationsRaiseWarmth() throws {
        let warm = try #require(ToneDerivation.scores(from: [
            (text: "thanks so much, love it! great work, really appreciate it!", weight: 1.0)]))
        let cold = try #require(ToneDerivation.scores(from: [
            (text: "the report is attached. review section two. send comments by five.", weight: 1.0)]))
        #expect(warm.warmth > cold.warmth)
    }
    @Test func weightsShiftTheBlend() throws {
        // Heavily-weighted brief text vs lightly-weighted long text → brevity leans brief.
        let mixed = try #require(ToneDerivation.scores(from: [
            (text: "ok. thanks. done.", weight: 1.0),
            (text: "i wanted to follow up regarding the discussion we had earlier this week about "
                 + "the quarterly planning process and all the various considerations", weight: 0.05),
        ]))
        #expect(mixed.brevity > 0.5)
    }
    @Test func deterministicAcrossInputOrder() {
        let corpus: [WeightedText] = [
            (text: "thanks for the update!", weight: 1.0),
            (text: "will do, no worries", weight: 0.7),
            (text: "the report is attached for review", weight: 0.4),
        ]
        #expect(ToneDerivation.scores(from: corpus) == ToneDerivation.scores(from: corpus.reversed()))
    }
    @Test func nonFiniteWeightDroppedNotDominant() throws {
        // Parity with PhraseExtractor's guard: an .infinity weight passes `> 0` but must be
        // dropped by `.isFinite`, else it poisons every weighted sum. (NaN/negative are already
        // caught by `> 0`; .infinity is the case that needs the finite check.)
        let withInf = try #require(ToneDerivation.scores(from: [
            (text: "the report is attached for review", weight: 1.0),
            (text: "flood the entire corpus with noise", weight: .infinity),
        ]))
        let solo = try #require(ToneDerivation.scores(from: [
            (text: "the report is attached for review", weight: 1.0)]))
        #expect(withInf == solo)
    }
}
