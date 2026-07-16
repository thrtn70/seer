import ApplicationServices
import AppKit
import SeerSupport

/// Resolves the caret's screen rect for a focused element via the parameterized
/// `kAXBoundsForRange` query, then validates + flips it into AppKit screen space.
enum CaretLocator {
    static func caretRect(element: AXUIElement, caretIndexUTF16: Int) -> CGRect? {
        var boundsRange = CFRange(location: caretIndexUTF16, length: 0)
        guard let axRange = AXValueCreate(.cfRange, &boundsRange) else { return nil }
        var boundsRef: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &boundsRef)
        guard err == .success, let br = boundsRef, CFGetTypeID(br) == AXValueGetTypeID() else { return nil }
        var axRect = CGRect.zero
        AXValueGetValue(br as! AXValue, .cgRect, &axRect)

        let primary = NSScreen.screens.first?.frame ?? .zero
        let flippedY = CaretGeometry.flipY(axTop: axRect.origin.y, height: axRect.height,
                                           primaryHeight: primary.height)
        let rect = CGRect(x: axRect.origin.x, y: flippedY, width: max(axRect.width, 2), height: axRect.height)
        return CaretGeometry.isValid(rect, primaryFrame: primary) ? rect : nil
    }
}
