import Foundation
import CoreGraphics

/// An immutable snapshot of the focused text field at capture time (§3.2).
public struct CaptureContext: Sendable {
    public let bundleID: String
    public let focusedRole: String            // e.g. "AXTextArea"
    public let focusedSubrole: String?        // "AXSecureTextField" ⇒ excluded upstream
    public let textBeforeCaret: String        // last ~500 chars
    public let textAfterCaret: String         // next ~200 chars
    public let selectionLength: Int           // >0 ⇒ suppress in v1
    public let caretRect: CGRect?             // validated AppKit screen rect; nil ⇒ pill
    public let prefixHash: UInt64             // FNV-1a over textBeforeCaret (KV-cache key, §4.6)
    public let capturedAt: ContinuousClock.Instant

    public init(bundleID: String, focusedRole: String, focusedSubrole: String?,
                textBeforeCaret: String, textAfterCaret: String, selectionLength: Int,
                caretRect: CGRect?, prefixHash: UInt64, capturedAt: ContinuousClock.Instant) {
        self.bundleID = bundleID; self.focusedRole = focusedRole; self.focusedSubrole = focusedSubrole
        self.textBeforeCaret = textBeforeCaret; self.textAfterCaret = textAfterCaret
        self.selectionLength = selectionLength; self.caretRect = caretRect
        self.prefixHash = prefixHash; self.capturedAt = capturedAt
    }
}
