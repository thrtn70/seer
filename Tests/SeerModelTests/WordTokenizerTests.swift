import Testing
@testable import SeerModel

@Suite struct WordTokenizerTests {
    @Test func splitsWordsWithTrailingSpaces() {
        #expect(WordTokenizer.wordChunks("issued a full refund") == ["issued ", "a ", "full ", "refund"])
    }
    @Test func joiningReproducesInput() {
        for s in [" leading", "trailing ", "a  b", "one", "", "  "] {
            #expect(WordTokenizer.wordChunks(s).joined() == s)
        }
    }
    @Test func leadingSpaceStaysWithFirstChunk() {
        #expect(WordTokenizer.wordChunks(" world here") == [" world ", "here"])
    }
    @Test func countsWordsInFullLine() {
        #expect(WordTokenizer.wordCount(of: "issued a full refund") == 4)
    }
    @Test func trailingSpacesDoNotAddWords() {
        #expect(WordTokenizer.wordCount(of: "issued ") == 1)
    }
    @Test func leadingSpaceDoesNotAddAWord() {
        #expect(WordTokenizer.wordCount(of: " world here") == 2)
    }
    @Test func emptyStringHasZeroWords() {
        #expect(WordTokenizer.wordCount(of: "") == 0)
    }
    @Test func allSpacesHaveZeroWords() {
        #expect(WordTokenizer.wordCount(of: "  ") == 0)
    }
    @Test func multipleSpacesBetweenWordsCountOnce() {
        #expect(WordTokenizer.wordCount(of: "a  b") == 2)
    }
    @Test func punctuationRunCountsAsWord() {
        #expect(WordTokenizer.wordCount(of: "refund.") == 1)
    }
}
