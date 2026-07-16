import Testing
@testable import SeerInference

@Suite struct UTF8PieceAssemblerTests {
    @Test func asciiPassesThroughImmediately() {
        var a = UTF8PieceAssembler()
        #expect(a.push([UInt8]("hello".utf8)) == "hello")
        #expect(a.flush() == "")
    }
    @Test func fourByteEmojiSplitAcrossTwoPushes() {
        // "🎉" = F0 9F 8E 89
        var a = UTF8PieceAssembler()
        #expect(a.push([0xF0, 0x9F]) == "")     // incomplete — nothing emitted yet
        #expect(a.push([0x8E, 0x89]) == "🎉")   // completes the codepoint
        #expect(a.flush() == "")
    }
    @Test func threeByteCJKSplit() {
        // "中" = E4 B8 AD
        var a = UTF8PieceAssembler()
        #expect(a.push([0xE4]) == "")
        #expect(a.push([0xB8, 0xAD]) == "中")
    }
    @Test func emitsCompletePrefixRetainsPartialTail() {
        // "a" + start of "中"
        var a = UTF8PieceAssembler()
        #expect(a.push([0x61, 0xE4, 0xB8]) == "a")  // emit 'a', retain E4 B8
        #expect(a.push([0xAD]) == "中")
    }
    @Test func flushOnTrulyIncompleteIsLossyNotCrash() {
        var a = UTF8PieceAssembler()
        #expect(a.push([0xF0, 0x9F]) == "")
        let tail = a.flush()                 // best-effort at end of stream
        #expect(tail == "\u{FFFD}" || tail == "")   // deterministic, no crash
    }
    @Test func multiByteFullyContainedInOnePush() {
        var a = UTF8PieceAssembler()
        #expect(a.push([UInt8]("héllo 🎉".utf8)) == "héllo 🎉")
    }
}
