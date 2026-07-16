import Testing
@testable import SeerInference

@Suite struct TokenPrefixTests {
    @Test func fullMatch() {
        #expect(TokenPrefix.commonLength([1,2,3], [1,2,3]) == 3)
    }
    @Test func appendOnly() {
        #expect(TokenPrefix.commonLength([1,2,3], [1,2,3,4,5]) == 3)
    }
    @Test func divergeMiddle() {
        #expect(TokenPrefix.commonLength([1,2,3,4], [1,2,9,4]) == 2)
    }
    @Test func noCommon() {
        #expect(TokenPrefix.commonLength([7,8], [1,2]) == 0)
    }
    @Test func emptyInputs() {
        #expect(TokenPrefix.commonLength([], [1,2]) == 0)
        #expect(TokenPrefix.commonLength([1,2], []) == 0)
    }
}
