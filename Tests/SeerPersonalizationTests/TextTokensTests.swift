import Testing
@testable import SeerPersonalization

@Suite struct TextTokensTests {
    // MARK: words

    @Test func wordsLowercaseAndSplitOnNonWordCharacters() {
        #expect(TextTokens.words("Thanks, FOR the update!") == ["thanks", "for", "the", "update"])
    }
    @Test func wordsKeepApostrophesAndHyphens() {
        #expect(TextTokens.words("don't re-run") == ["don't", "re-run"])
    }
    @Test func wordsStructurallyDropChatMLMarkers() {
        // "<", "|", "_" are separators, so ChatML control tokens dissolve into letter runs.
        #expect(TextTokens.words("<|im_start|>hi<|im_end|>") == ["im", "start", "hi", "im", "end"])
    }
    @Test func wordsOnPunctuationOnlyIsEmpty() {
        #expect(TextTokens.words("").isEmpty)
        #expect(TextTokens.words("   !!!  ").isEmpty)
    }
    @Test func wordsDropPunctuationOnlyAndTrimEdgePunctuation() {
        // A token must be a letter run with only *interior* apostrophes/hyphens: bare punctuation
        // is dropped and leading/trailing '/- are stripped. Otherwise "cost - benefit" leaks a
        // "-" token and "'hi'" keeps its quotes — junk that would seed the derived phrase table
        // (bigrams like "cost -" / "- benefit" in the §7.3 descriptor / KV-cache prefix).
        #expect(TextTokens.words("cost - benefit") == ["cost", "benefit"])
        #expect(TextTokens.words("-- em --- dash") == ["em", "dash"])
        #expect(TextTokens.words("' '' ' quote") == ["quote"])
        #expect(TextTokens.words("she said 'hi' loudly") == ["she", "said", "hi", "loudly"])
        // Interior '/- are still preserved.
        #expect(TextTokens.words("don't re-run") == ["don't", "re-run"])
    }

    // MARK: sentences

    @Test func sentencesSplitOnTerminatorsAndNewline() {
        #expect(TextTokens.sentences("Hi there. How are you? Great! New\nline")
                == ["Hi there", "How are you", "Great", "New", "line"])
    }
    @Test func sentencesDropBlankSegments() {
        // Runs of terminators and whitespace-only gaps yield no empty sentences.
        #expect(TextTokens.sentences("Wait... really?!  \n\n Yes.") == ["Wait", "really", "Yes"])
    }
    @Test func sentencesWithoutTerminatorIsOneSentence() {
        #expect(TextTokens.sentences("no terminator here") == ["no terminator here"])
    }
    @Test func sentencesOnBlankOrTerminatorOnlyIsEmpty() {
        #expect(TextTokens.sentences("").isEmpty)
        #expect(TextTokens.sentences("  .  ! ? \n ").isEmpty)
    }
}
