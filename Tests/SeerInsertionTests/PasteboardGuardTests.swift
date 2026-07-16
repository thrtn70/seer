import Testing
@testable import SeerInsertion

@Suite struct PasteboardGuardTests {
    @Test func restoreOnlyWhenUnchanged() {
        #expect(PasteboardGuard.shouldRestore(afterSetChangeCount: 7, currentChangeCount: 7) == true)
    }
    @Test func noRestoreWhenSomethingElseChangedIt() {
        #expect(PasteboardGuard.shouldRestore(afterSetChangeCount: 7, currentChangeCount: 8) == false)
    }
}
