import Testing
import Foundation
@testable import SeerPersonalization

@Suite struct AcceptedSampleTests {
    @Test func initCapsBeforeCaretAt200() {
        // Position-distinguishable content (A–Z cycling) so suffix(cap) != prefix(cap): pins that
        // the cap keeps the text NEAREST the caret (the tail), not the earliest chars. A
        // suffix→prefix mutation in AcceptedSample.init flips which end survives and fails here —
        // a homogeneous "xxxx…" input could not tell the two apart.
        let cap = AcceptedSample.beforeCaretCap
        let long = String((0..<500).map { Character(UnicodeScalar(65 + UInt8($0 % 26))) })
        let s = AcceptedSample(bundleID: "com.apple.TextEdit", focusedSubrole: nil,
                               completion: "hi", beforeCaret: long, timestamp: Date(timeIntervalSince1970: 0))
        #expect(s.beforeCaret.count == cap)
        #expect(s.beforeCaret == String(long.suffix(cap)))
        #expect(s.beforeCaret != String(long.prefix(cap)))   // suffix, not prefix — kills the mutation
    }
    @Test func initKeepsShortBeforeCaretIntact() {
        let s = AcceptedSample(bundleID: "b", focusedSubrole: "AXSecureTextField",
                               completion: "c", beforeCaret: "abc", timestamp: Date(timeIntervalSince1970: 5))
        #expect(s.beforeCaret == "abc")
        #expect(s.focusedSubrole == "AXSecureTextField")
        #expect(s.completion == "c")
        #expect(s.bundleID == "b")
        #expect(s.timestamp == Date(timeIntervalSince1970: 5))
    }
}
