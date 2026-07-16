import Testing
import Foundation
@testable import SeerCoordinator

@Suite struct FocusObserverTests {
    @Test @MainActor func retargetToZeroLeavesNoObservation() {
        let o = FocusObserver()
        o.retarget(to: 0)
        #expect(o.observedPID == 0)
    }
    @Test @MainActor func retargetToSelfIsIgnored() {
        let o = FocusObserver()
        o.retarget(to: ProcessInfo.processInfo.processIdentifier)
        #expect(o.observedPID == 0)   // never observe our own process
    }
    @Test @MainActor func startStopDoNotCrash() {
        let o = FocusObserver()
        var fired = 0
        o.onInvalidate = { fired += 1 }
        o.start(); o.stop()
        #expect(fired == 0)   // start()+immediate stop() must not fire onInvalidate
    }
}
