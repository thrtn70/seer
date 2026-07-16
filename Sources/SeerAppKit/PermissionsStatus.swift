import SeerCapture
import SeerInput

/// A snapshot of the two TCC grants Seer needs.
public struct PermissionsStatus: Equatable, Sendable {
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public init(accessibility: Bool, inputMonitoring: Bool) {
        self.accessibility = accessibility; self.inputMonitoring = inputMonitoring
    }
    public var allGranted: Bool { accessibility && inputMonitoring }
    /// Live snapshot. `promptAccessibility: true` triggers the AX trust prompt once.
    public static func snapshot(promptAccessibility: Bool = false) -> PermissionsStatus {
        PermissionsStatus(accessibility: Permissions.hasAccessibility(prompt: promptAccessibility),
                          inputMonitoring: InputMonitoring.has())
    }
}
