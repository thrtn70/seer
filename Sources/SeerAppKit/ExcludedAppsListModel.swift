import Foundation

/// A row in the Settings "Paused apps" table. `installed == false` means the bundle id no
/// longer resolves to an app on disk; the row shows the raw id and stays removable (stale
/// exclusions accumulate — the menu pauses whatever is frontmost, including apps later
/// uninstalled — and must be purgeable).
public struct ExcludedAppRow: Equatable, Sendable {
    public let bundleID: String
    public let displayName: String
    public let installed: Bool
    public init(bundleID: String, displayName: String, installed: Bool) {
        self.bundleID = bundleID; self.displayName = displayName; self.installed = installed
    }
}

public enum ExcludedAppsListModel {
    /// Rows for the paused-apps table. `resolveName` maps a bundle id to a localized app
    /// name (nil/blank ⇒ not installed — a whitespace-only name would render an invisible
    /// row that claims to be installed). Sorted with `localizedStandardCompare` — the
    /// Finder-style comparison Apple prescribes for names shown in lists and tables, so
    /// "Xcode 9" precedes "Xcode 15" — plus a bundle-id tiebreak, so ordering is total and
    /// deterministic (`sorted()` is not stable — the tiebreak is what makes results
    /// reproducible across Set iteration orders).
    public static func rows(bundleIDs: Set<String>,
                            resolveName: (String) -> String?) -> [ExcludedAppRow] {
        bundleIDs.map { id in
            if let name = resolveName(id), !name.trimmingCharacters(in: .whitespaces).isEmpty {
                return ExcludedAppRow(bundleID: id, displayName: name, installed: true)
            }
            return ExcludedAppRow(bundleID: id, displayName: id, installed: false)
        }
        .sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.bundleID < $1.bundleID
        }
    }
}
