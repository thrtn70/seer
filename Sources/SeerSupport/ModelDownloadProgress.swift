import Foundation

/// Pure formatting for the setup window's progress line — kept out of the UI layer so it can be
/// tested without AppKit.
public enum ModelDownloadProgress {
    /// `nil` when the server sent no expected length, so callers can fall back to an
    /// indeterminate progress bar rather than rendering a bogus 0%.
    public static func fraction(completed: Int64, total: Int64) -> Double? {
        guard total > 0 else { return nil }
        return min(1.0, max(0.0, Double(completed) / Double(total)))
    }

    /// e.g. "412 MB of 1.12 GB (37%)", or "412 MB downloaded" when the total is unknown.
    public static func describe(completed: Int64, total: Int64) -> String {
        let done = ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)
        guard let f = fraction(completed: completed, total: total) else { return "\(done) downloaded" }
        let all = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return "\(done) of \(all) (\(Int(f * 100))%)"
    }
}
