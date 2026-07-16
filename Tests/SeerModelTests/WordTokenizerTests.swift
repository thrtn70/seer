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
}
