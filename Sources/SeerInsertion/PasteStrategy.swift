import AppKit
import CoreGraphics

/// Paste insertion: pause tap → save clipboard (+changeCount) → set suggestion → synthetic ⌘V →
/// after a bounded delay restore the clipboard iff still ours → resume tap. Single op for undo.
public enum PasteStrategy {
    public static let restoreDelay: TimeInterval = 0.12
    private static let vKey: CGKeyCode = 9

    @MainActor
    public static func insert(_ text: String, gate: KeystrokeGate, pasteboard pb: NSPasteboard = .general) {
        guard !text.isEmpty else { return }
        gate.pause()
        let original = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        let afterSet = pb.changeCount

        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true); down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false); up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            if PasteboardGuard.shouldRestore(afterSetChangeCount: afterSet, currentChangeCount: pb.changeCount) {
                pb.clearContents()
                if let original { pb.setString(original, forType: .string) }
            }
            gate.resume()
        }
    }
}
