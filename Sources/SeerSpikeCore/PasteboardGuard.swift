public enum PasteboardGuard {
    /// We restore the user's clipboard only if nothing changed it since our own set.
    public static func shouldRestore(afterSetChangeCount: Int, currentChangeCount: Int) -> Bool {
        currentChangeCount == afterSetChangeCount
    }
}
