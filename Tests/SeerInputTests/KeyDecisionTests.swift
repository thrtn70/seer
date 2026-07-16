import Testing
import SeerModel
@testable import SeerInput

@Suite struct KeyDecisionTests {
    @Test func idleTabPassesThrough() {
        #expect(KeyDecision.action(state: .idle, keyCode: KeyCodes.tab, hasShift: false) == .passThrough)
    }
    @Test func idleAnyKeyPassesThrough() {
        #expect(KeyDecision.action(state: .idle, keyCode: 5, hasShift: false) == .passThrough)
    }
    @Test func showingTabAcceptsNextWord() {
        #expect(KeyDecision.action(state: .showing, keyCode: KeyCodes.tab, hasShift: false) == .accept(.nextWord))
    }
    @Test func showingShiftTabAcceptsWholeLine() {
        #expect(KeyDecision.action(state: .showing, keyCode: KeyCodes.tab, hasShift: true) == .accept(.wholeLine))
    }
    @Test func showingEscDismisses() {
        #expect(KeyDecision.action(state: .showing, keyCode: KeyCodes.escape, hasShift: false) == .dismiss)
    }
    @Test func showingOtherKeyTypeOverDismisses() {
        #expect(KeyDecision.action(state: .showing, keyCode: 5, hasShift: false) == .typeOverDismiss)
    }
    @Test func acceptingPassesThrough() {
        #expect(KeyDecision.action(state: .accepting, keyCode: KeyCodes.tab, hasShift: false) == .passThrough)
    }
}
