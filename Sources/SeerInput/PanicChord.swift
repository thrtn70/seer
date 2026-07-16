import CoreGraphics

/// The global panic/pause hotkey (§4.10): ⌃⌥⌘. — instantly dismiss any suggestion, cancel
/// in-flight inference, and toggle the global pause. Detected in the keystroke tap (no
/// separate global-hotkey registration needed).
public enum PanicChord {
    public static func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == KeyCodes.period
            && flags.contains(.maskControl)
            && flags.contains(.maskAlternate)
            && flags.contains(.maskCommand)
    }
}
