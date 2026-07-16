import ApplicationServices
import AppKit
import SeerModel
import SeerSupport

/// On-demand capture of the focused text field → CaptureContext.
/// MainActor-isolated (AX reads + AppKit are main-thread-affine). Every cross-process AX
/// read is bounded by a 250 ms messaging timeout (the §3.3 watchdog) so a hung target app
/// yields nil instead of stalling. Secure fields are excluded fail-closed (§6).
@MainActor
public enum CaptureService {
    public static let watchdogSeconds: Float = 0.25
    public static let beforeCaretCap = 500
    public static let afterCaretCap = 200

    public static func capture() -> CaptureContext? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, watchdogSeconds)

        guard let element = focusedElement(system) else { return nil }
        AXUIElementSetMessagingTimeout(element, watchdogSeconds)

        // Secure-field gate (fail-closed, §6): never capture from a password field.
        let subrole = copyString(element, kAXSubroleAttribute)
        if subrole == "AXSecureTextField" { return nil }

        let role = copyString(element, kAXRoleAttribute) ?? ""
        let bundle = bundleID(of: element)
        let value = copyString(element, kAXValueAttribute) ?? ""

        // Selected range → caret index (UTF-16). Absent ⇒ pill-path context, no caret.
        guard let range = copyRange(element, kAXSelectedTextRangeAttribute) else {
            let before = String(value.suffix(beforeCaretCap))
            return CaptureContext(
                bundleID: bundle, focusedRole: role, focusedSubrole: subrole,
                textBeforeCaret: before, textAfterCaret: "", selectionLength: 0,
                caretRect: nil, prefixHash: Hashing.fnv1a64(before.utf8),
                capturedAt: ContinuousClock().now)
        }

        let caretIndex = max(0, min(range.location, value.utf16.count))
        let (before, after) = TextSlice.aroundCaret(value: value, caretUTF16: caretIndex)
        let beforeCapped = String(before.suffix(beforeCaretCap))
        let afterCapped = String(after.prefix(afterCaretCap))
        let caret = CaretLocator.caretRect(element: element, caretIndexUTF16: caretIndex)

        return CaptureContext(
            bundleID: bundle, focusedRole: role, focusedSubrole: subrole,
            textBeforeCaret: beforeCapped, textAfterCaret: afterCapped,
            selectionLength: range.length, caretRect: caret,
            prefixHash: Hashing.fnv1a64(beforeCapped.utf8), capturedAt: ContinuousClock().now)
    }

    // MARK: AX helpers

    private static func focusedElement(_ system: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let r = ref, CFGetTypeID(r) == AXUIElementGetTypeID() else { return nil }
        return (r as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func copyRange(_ element: AXUIElement, _ attr: String) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
              let r = ref, CFGetTypeID(r) == AXValueGetTypeID() else { return nil }
        var range = CFRange(location: 0, length: 0)
        AXValueGetValue(r as! AXValue, .cfRange, &range)
        return range
    }

    private static func bundleID(of element: AXUIElement) -> String {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else { return "" }
        return app.bundleIdentifier ?? ""
    }
}
