import Testing
import CoreGraphics
@testable import SeerInput

@Suite struct PanicChordTests {
    private let mods: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    @Test func matchesCtrlOptCmdPeriod() {
        #expect(PanicChord.matches(keyCode: KeyCodes.period, flags: mods) == true)
    }
    @Test func extraModifierStillMatches() {  // contains-based: shift too is fine
        #expect(PanicChord.matches(keyCode: KeyCodes.period, flags: [.maskControl, .maskAlternate, .maskCommand, .maskShift]) == true)
    }
    @Test func missingCommandDoesNotMatch() {
        #expect(PanicChord.matches(keyCode: KeyCodes.period, flags: [.maskControl, .maskAlternate]) == false)
    }
    @Test func wrongKeyDoesNotMatch() {
        #expect(PanicChord.matches(keyCode: KeyCodes.tab, flags: mods) == false)
    }
}
