import Testing
@testable import SeerOverlay

@Suite struct GhostTextTests {
    @Test func emptyIsNotRenderable() {
        #expect(GhostText.sanitize("") == "")
        #expect(GhostText.shouldRender("") == false)
    }
    @Test func allWhitespaceIsNotRenderable() {
        #expect(GhostText.sanitize("   ") == "")
        #expect(GhostText.shouldRender("\n\t") == false)   // controls stripped → empty
    }
    @Test func leadingSpaceIsPreserved() {
        #expect(GhostText.sanitize(" Hello") == " Hello")  // model's leading space kept
        #expect(GhostText.shouldRender(" Hello") == true)
    }
    @Test func controlCharsAreStripped() {
        #expect(GhostText.sanitize("a\nb") == "ab")        // newline is a control char
    }
    @Test func plainTextUnchanged() {
        #expect(GhostText.sanitize("world") == "world")
    }

    @Test func allDigitsNotDisplayable() {
        #expect(GhostText.displayable("100000000000000000000000") == "")   // the reported "random numbers"
    }
    @Test func allPunctuationNotDisplayable() {
        #expect(GhostText.displayable("____") == "")
        #expect(GhostText.displayable(" ____1____ ") == "")                // punctuation + digit, no letter
    }
    @Test func digitsThenLetterIsDisplayedInFull() {
        #expect(GhostText.displayable("3D printing") == "3D printing")     // has a letter ⇒ shown unchanged
    }
    @Test func leadingSpaceBeforeLetterPreserved() {
        #expect(GhostText.displayable(" you") == " you")
    }
    @Test func plainTextDisplayable() {
        #expect(GhostText.displayable("Hello") == "Hello")
    }
    @Test func emptyNotDisplayable() {
        #expect(GhostText.displayable("") == "")
    }
}
