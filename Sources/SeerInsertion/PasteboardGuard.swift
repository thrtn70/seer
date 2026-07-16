/// Restore the user's clipboard only if nothing else changed it since our own set.
public enum PasteboardGuard {
    public static func shouldRestore(afterSetChangeCount: Int, currentChangeCount: Int) -> Bool {
        currentChangeCount == afterSetChangeCount
    }
}
