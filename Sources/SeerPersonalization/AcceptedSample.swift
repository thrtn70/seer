import Foundation

/// One accepted-suggestion learning signal (§7.1, accept-only). `beforeCaret` is capped at
/// 200 chars at the boundary (§7.3 `recent_acceptance.before_caret≤200`). It is stored for
/// Phase 12.x (export redaction) and has no consumer in Phase 12 — a recorded decision, not
/// an accident (parent spec §7.3 amendment).
public struct AcceptedSample: Sendable, Equatable {
    public static let beforeCaretCap = 200
    public let bundleID: String
    public let focusedSubrole: String?
    public let completion: String
    public let beforeCaret: String
    public let timestamp: Date
    public init(bundleID: String, focusedSubrole: String?, completion: String,
                beforeCaret: String, timestamp: Date) {
        self.bundleID = bundleID
        self.focusedSubrole = focusedSubrole
        self.completion = completion
        self.beforeCaret = String(beforeCaret.suffix(Self.beforeCaretCap))
        self.timestamp = timestamp
    }
}
