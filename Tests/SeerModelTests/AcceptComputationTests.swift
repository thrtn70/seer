import Testing
@testable import SeerModel

@Suite struct AcceptComputationTests {
    @Test func nextWordTakesFirstChunk() {
        let r = AcceptComputation.apply(chunks: ["issued ", "a ", "refund"], kind: .nextWord)
        #expect(r.toInsert == "issued ")
        #expect(r.remaining == ["a ", "refund"])
    }
    @Test func wholeLineJoinsAll() {
        let r = AcceptComputation.apply(chunks: ["issued ", "a ", "refund"], kind: .wholeLine)
        #expect(r.toInsert == "issued a refund")
        #expect(r.remaining.isEmpty)
    }
    @Test func emptyChunksYieldNothing() {
        let r = AcceptComputation.apply(chunks: [], kind: .nextWord)
        #expect(r.toInsert == "")
        #expect(r.remaining.isEmpty)
    }
    @Test func lastWordLeavesEmptyRemaining() {
        let r = AcceptComputation.apply(chunks: ["refund"], kind: .nextWord)
        #expect(r.toInsert == "refund")
        #expect(r.remaining.isEmpty)
    }
}
