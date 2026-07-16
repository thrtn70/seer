import ApplicationServices
import AppKit
import SeerSpikeCore

struct CaretCapture {
    let textBeforeCaret: String
    let caretRect: CGRect?
    let isSecure: Bool
    let font: NSFont
}

enum AXCapture {
    static func capture() -> CaretCapture? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              CFGetTypeID(focusedRef!) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedRef as! AXUIElement

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        if (subroleRef as? String) == "AXSecureTextField" {
            return CaretCapture(textBeforeCaret: "", caretRect: nil, isSecure: true, font: .systemFont(ofSize: 13))
        }

        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let value = (valueRef as? String) ?? ""

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rv = rangeRef, CFGetTypeID(rv) == AXValueGetTypeID()
        else {
            return CaretCapture(textBeforeCaret: value, caretRect: nil, isSecure: false, font: fieldFont(element))
        }
        var cfRange = CFRange(location: 0, length: 0)
        AXValueGetValue(rv as! AXValue, .cfRange, &cfRange)
        let utf16 = value.utf16
        let caretIndex = max(0, min(cfRange.location, utf16.count))   // UTF-16 offset (AX semantics)
        let before: String
        if let i16 = utf16.index(utf16.startIndex, offsetBy: caretIndex, limitedBy: utf16.endIndex),
           let sIdx = i16.samePosition(in: value) {
            before = String(value[..<sIdx])
        } else {
            before = value
        }

        var boundsRange = CFRange(location: caretIndex, length: 0)
        guard let axRange = AXValueCreate(.cfRange, &boundsRange) else {
            return CaretCapture(textBeforeCaret: before, caretRect: nil, isSecure: false, font: fieldFont(element))
        }
        var boundsRef: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &boundsRef)
        guard err == .success, let br = boundsRef, CFGetTypeID(br) == AXValueGetTypeID() else {
            return CaretCapture(textBeforeCaret: before, caretRect: nil, isSecure: false, font: fieldFont(element))
        }
        var axRect = CGRect.zero
        AXValueGetValue(br as! AXValue, .cgRect, &axRect)

        let primary = NSScreen.screens.first?.frame ?? .zero
        let flippedY = Geometry.flipY(axTop: axRect.origin.y, height: axRect.height, primaryHeight: primary.height)
        let rect = CGRect(x: axRect.origin.x, y: flippedY, width: max(axRect.width, 2), height: axRect.height)
        let caretRect = Geometry.isValid(rect, primaryFrame: primary) ? rect : nil
        return CaretCapture(textBeforeCaret: before, caretRect: caretRect, isSecure: false, font: fieldFont(element))
    }

    private static func fieldFont(_ element: AXUIElement) -> NSFont {
        .systemFont(ofSize: 13)
    }
}
