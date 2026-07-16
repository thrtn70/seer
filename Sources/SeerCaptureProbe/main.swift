import AppKit
import Foundation
import SeerCapture
import SeerModel

// Diagnostic probe: every second, capture the focused field and print its CaptureContext +
// the inline/pill decision. Focus TextEdit / Mail / a password field / an Electron app and
// watch the output. Needs Accessibility permission granted to THIS binary.

guard Permissions.hasAccessibility(prompt: true) else {
    print("[probe] Accessibility NOT granted. Grant it for this binary in System Settings → "
        + "Privacy & Security → Accessibility, then relaunch.")
    exit(2)
}
print("[probe] Accessibility granted. Capturing focused field every 1s. Ctrl-C to stop.")

// A seed known-bad (Electron/web) bundle list; expanded as the compat matrix grows.
let knownBad: Set<String> = ["com.tinyspeck.slackmacgap", "com.microsoft.VSCode", "com.github.atom"]

func tick() {
    MainActor.assumeIsolated {
        guard let ctx = CaptureService.capture() else {
            print("[probe] (no capturable focused field / secure field / AX timeout)")
            return
        }
        let mouse = NSEvent.mouseLocation
        let mode = FallbackDetector.renderMode(
            caretRect: ctx.caretRect, hasSelectedRange: ctx.caretRect != nil,
            bundleID: ctx.bundleID, knownBadBundles: knownBad,
            mousePoint: mouse, windowTopAnchor: nil)
        let caret = ctx.caretRect.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "nil"
        let tail = String(ctx.textBeforeCaret.suffix(40)).replacingOccurrences(of: "\n", with: "⏎")
        let modeStr: String
        switch mode { case .inline: modeStr = "INLINE"; case .pill(let p): modeStr = "PILL@\(Int(p.x)),\(Int(p.y))" }
        print("[probe] \(ctx.bundleID) role=\(ctx.focusedRole) sub=\(ctx.focusedSubrole ?? "-") "
            + "caret=[\(caret)] sel=\(ctx.selectionLength) hash=\(ctx.prefixHash) mode=\(modeStr) before=…\(tail)")
    }
}

let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in tick() }
RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
