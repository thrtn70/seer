/// The insertion service pauses keystroke interception around a synthetic paste so the ⌘V
/// keydown is not re-intercepted (the central fix for the stray-space/double-insert race).
@MainActor
public protocol KeystrokeGate: AnyObject {
    func pause()
    func resume()
}
