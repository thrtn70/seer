import Foundation

/// Pure (profile, sample) → profile. Drops secure-subrole samples (§6 defense in depth) and
/// blank completions; appends and caps recents per app.
public enum ProfileReducer {
    public static let recentsCap = 200
    public static let secureSubrole = "AXSecureTextField"

    public static func reduce(_ profile: StyleProfile, sample: AcceptedSample) -> StyleProfile {
        guard sample.focusedSubrole != secureSubrole else { return profile }
        guard !sample.completion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return profile }
        var apps = profile.apps
        var recents = apps[sample.bundleID]?.recents ?? []
        recents.append(StoredAcceptance(completion: sample.completion,
                                        beforeCaret: sample.beforeCaret,
                                        timestamp: sample.timestamp))
        if recents.count > recentsCap { recents.removeFirst(recents.count - recentsCap) }
        apps[sample.bundleID] = AppProfile(recents: recents)
        return StyleProfile(apps: apps)
    }
}
