import CoreGraphics

/// macOS virtual key codes used by the keystroke tap and paste insertion.
public enum KeyCodes {
    public static let tab: Int64 = 48
    public static let escape: Int64 = 53
    public static let period: Int64 = 47   // '.' — global panic hotkey (⌃⌥⌘.)
    public static let v: CGKeyCode = 9   // ⌘V paste
}
