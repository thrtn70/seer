import Testing
@testable import SeerCoordinator

@Suite struct TriggerGateTests {
    @Test func requiresTwoCharsAndALetter() {
        #expect(TriggerGate.shouldRequest(textBeforeCaret: "ab") == true)
        #expect(TriggerGate.shouldRequest(textBeforeCaret: "a") == false)
        #expect(TriggerGate.shouldRequest(textBeforeCaret: "12") == false)
        #expect(TriggerGate.shouldRequest(textBeforeCaret: "") == false)
        #expect(TriggerGate.shouldRequest(textBeforeCaret: "x ") == true)
    }
}
