import Foundation

/// Persisted app-layer settings (UserDefaults). Injectable suite for tests.
public struct AppSettings {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private enum Key {
        static let enabled = "seer.enabled"
        static let paused = "seer.pausedBundles"
        static let onboarded = "seer.onboardingComplete"
    }
    public var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }   // default ON
        nonmutating set { defaults.set(newValue, forKey: Key.enabled) }
    }
    public var pausedBundles: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.paused) ?? []) }
        nonmutating set { defaults.set(Array(newValue).sorted(), forKey: Key.paused) }
    }
    public var onboardingComplete: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        nonmutating set { defaults.set(newValue, forKey: Key.onboarded) }
    }
}
