import Testing
import AppKit
@testable import SeerInsertion

@MainActor
private final class SpyGate: KeystrokeGate {
    var paused = 0; var resumed = 0
    func pause() { paused += 1 }
    func resume() { resumed += 1 }
}

@Suite struct PasteStrategyTests {
    @Test @MainActor func setsPasteboardAndPausesGate() {
        let pb = NSPasteboard(name: NSPasteboard.Name("seer.test.\(UInt64.random(in: 0...(.max)))"))
        pb.clearContents(); pb.setString("ORIG", forType: .string)
        let gate = SpyGate()
        PasteStrategy.insert(" world", gate: gate, pasteboard: pb)
        #expect(gate.paused == 1)                        // tap paused before paste
        #expect(pb.string(forType: .string) == " world") // suggestion placed on pasteboard
    }
}
