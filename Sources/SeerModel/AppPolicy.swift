/// Pure decision: should Seer offer a suggestion, given global on/off + per-app pause.
public enum AppPolicy {
    public static func shouldSuggest(enabled: Bool, pausedBundles: Set<String>, bundleID: String) -> Bool {
        enabled && !pausedBundles.contains(bundleID)
    }
}
