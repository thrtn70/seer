import Foundation

/// The persisted corpus: recent acceptances per app, and nothing else. Phrases and tone are
/// DERIVED from this at snapshot time (single source of truth — no stored aggregate can
/// drift from the corpus, and decay falls out of the timestamps).
public struct StyleProfile: Codable, Equatable, Sendable {
    public var apps: [String: AppProfile]
    public init(apps: [String: AppProfile]) { self.apps = apps }
    public static let empty = StyleProfile(apps: [:])
}

public struct AppProfile: Codable, Equatable, Sendable {
    /// Oldest first, newest last; capped by ProfileReducer.recentsCap.
    public var recents: [StoredAcceptance]
    public init(recents: [StoredAcceptance]) { self.recents = recents }
}

public struct StoredAcceptance: Codable, Equatable, Sendable {
    public let completion: String
    public let beforeCaret: String
    public let timestamp: Date
    public init(completion: String, beforeCaret: String, timestamp: Date) {
        self.completion = completion; self.beforeCaret = beforeCaret; self.timestamp = timestamp
    }
}
