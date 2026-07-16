import CoreGraphics

/// Input Monitoring (event-listen) TCC permission — required for the keystroke tap.
public enum InputMonitoring {
    public static func has() -> Bool { CGPreflightListenEventAccess() }
    @discardableResult
    public static func request() -> Bool { CGRequestListenEventAccess() }
}
