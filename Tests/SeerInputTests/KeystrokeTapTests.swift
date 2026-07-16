import Testing
import CoreGraphics
@testable import SeerInput

@Suite struct KeystrokeTapTests {
    @Test @MainActor func constructsAndReportsNotRunningBeforeStart() {
        let tap = KeystrokeTap()
        #expect(tap.isRunning == false)
        tap.pause(); tap.resume()   // no-ops before start: must not crash
        #expect(tap.isRunning == false)
    }
}
