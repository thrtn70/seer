/// Whether a suggestion should be requested for the given text-before-caret.
/// Single source of truth (replaces the probe-era `>= 3` stream guard).
public enum TriggerGate {
    public static func shouldRequest(textBeforeCaret: String) -> Bool {
        textBeforeCaret.count >= 2 && textBeforeCaret.contains(where: { $0.isLetter })
    }
}
