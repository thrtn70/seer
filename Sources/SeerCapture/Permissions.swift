import ApplicationServices

/// Minimal Accessibility-trust check for the capture probe. (Full onboarding/TCC recovery
/// is a later app sub-plan.)
public enum Permissions {
    public static func hasAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }
}
