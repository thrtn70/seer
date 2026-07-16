import Testing
@testable import SeerCapture

@Suite struct TextSliceTests {
    @Test func splitsAsciiAtCaret() {
        let (before, after) = TextSlice.aroundCaret(value: "hello world", caretUTF16: 5)
        #expect(before == "hello")
        #expect(after == " world")
    }
    @Test func caretAtStart() {
        let (before, after) = TextSlice.aroundCaret(value: "abc", caretUTF16: 0)
        #expect(before == "")
        #expect(after == "abc")
    }
    @Test func caretAtEnd() {
        let (before, after) = TextSlice.aroundCaret(value: "abc", caretUTF16: 3)
        #expect(before == "abc")
        #expect(after == "")
    }
    @Test func respectsUTF16OffsetsForAstralChars() {
        let (before, after) = TextSlice.aroundCaret(value: "🎉x", caretUTF16: 2)
        #expect(before == "🎉")
        #expect(after == "x")
    }
    @Test func clampsOutOfRangeCaret() {
        let (before, after) = TextSlice.aroundCaret(value: "ab", caretUTF16: 99)
        #expect(before == "ab")
        #expect(after == "")
    }
}
