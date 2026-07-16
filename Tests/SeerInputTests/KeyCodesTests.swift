import Testing
@testable import SeerInput

@Suite struct KeyCodesTests {
    @Test func macVirtualKeyCodes() {
        #expect(KeyCodes.tab == 48)
        #expect(KeyCodes.escape == 53)
        #expect(KeyCodes.v == 9)
    }
}
