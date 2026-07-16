import AppKit
import SeerSpikeCore

enum Inserter {
    @MainActor
    static func insert(_ text: String, tap: KeystrokeTap) {
        guard !text.isEmpty else { return }
        tap.pause()
        let pb = NSPasteboard.general
        let original = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        let afterSet = pb.changeCount

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        if down == nil || up == nil { NSLog("[seer] failed to synthesize paste keystroke") }
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if PasteboardGuard.shouldRestore(afterSetChangeCount: afterSet, currentChangeCount: pb.changeCount) {
                pb.clearContents()
                if let original { pb.setString(original, forType: .string) }
            }
            tap.resume()
        }
    }
}
