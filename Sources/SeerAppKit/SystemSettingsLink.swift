import Foundation

/// Deep links to the two System Settings → Privacy panes Seer needs.
public enum SystemSettingsLink {
    public static let accessibility = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    public static let inputMonitoring = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
}
