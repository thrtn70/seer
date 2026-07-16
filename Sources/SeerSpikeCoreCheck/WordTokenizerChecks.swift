import SeerSpikeCore

func runWordTokenizerChecks(_ c: Check) {
    c.equal(WordTokenizer.wordChunks("issued a full refund"),
            ["issued ", "a ", "full ", "refund"], "split with trailing space")
    c.expect(WordTokenizer.wordChunks("hello world").last == "world", "final word has no trailing space")
    c.equal(WordTokenizer.wordChunks("the quick brown fox").joined(), "the quick brown fox", "reassembly equals input")
    c.equal(WordTokenizer.wordChunks(""), [], "empty string")
    c.equal(WordTokenizer.wordChunks(" hi there"), [" hi ", "there"], "leading space preserved")
}
