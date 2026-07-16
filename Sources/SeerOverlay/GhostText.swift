import Foundation

/// Pure token-stream → display-string logic. No AppKit.
public enum GhostText {
    /// The renderable ghost string, or "" if nothing should be shown. Strips control
    /// characters (incl. newline/tab — ghost text is single-line); preserves a leading
    /// space the model emits. Returns "" for empty or all-whitespace input.
    public static func sanitize(_ raw: String) -> String {
        let stripped = String(raw.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        })
        if stripped.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        return stripped
    }

    /// Whether `sanitize` would yield anything renderable.
    public static func shouldRender(_ raw: String) -> Bool { !sanitize(raw).isEmpty }

    /// Display string for ghost text: sanitized, but withheld (returns "") until it contains
    /// at least one letter. This suppresses leading all-digit / all-punctuation degenerate
    /// model output (e.g. "100000…") on the placeholder prompt. Content-preserving: once a
    /// letter appears the full sanitized text (incl. any leading space) is shown.
    /// DISPLAY-only gate — Phase 1D insertion must use the raw suggestion, not this.
    public static func displayable(_ raw: String) -> String {
        let s = sanitize(raw)
        guard s.contains(where: { $0.isLetter }) else { return "" }
        return s
    }
}
