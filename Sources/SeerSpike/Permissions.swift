import ApplicationServices
import CoreGraphics

enum Permissions {
    static func hasAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func hasInputMonitoring() -> Bool { CGPreflightListenEventAccess() }

    @discardableResult
    static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }
}
