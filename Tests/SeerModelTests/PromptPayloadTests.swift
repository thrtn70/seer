import Testing
@testable import SeerModel

@Suite struct PromptPayloadTests {
    @Test func defaultsToNonSpecial() {
        let p = PromptPayload(stablePrefix: "a", context: "b")
        #expect(p.parseSpecial == false)
        #expect(p.fullText == "ab")
    }
    @Test func carriesParseSpecial() {
        let p = PromptPayload(stablePrefix: "sys", context: "ctx", parseSpecial: true)
        #expect(p.parseSpecial == true)
        #expect(p.fullText == "sysctx")
    }
    @Test func parseSpecialParticipatesInEquality() {
        let a = PromptPayload(stablePrefix: "x", context: "y", parseSpecial: true)
        let b = PromptPayload(stablePrefix: "x", context: "y", parseSpecial: false)
        #expect(a != b)
    }
}
