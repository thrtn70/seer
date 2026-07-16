import Testing
import Foundation
@testable import SeerAppKit

@Suite struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "seer.test.\(UInt64.random(in: 0...(.max)))"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    @Test func enabledDefaultsTrue() {
        #expect(AppSettings(defaults: freshDefaults()).enabled == true)
    }
    @Test func enabledRoundTrips() {
        let s = AppSettings(defaults: freshDefaults())
        s.enabled = false
        #expect(s.enabled == false)
    }
    @Test func pausedBundlesRoundTrip() {
        let s = AppSettings(defaults: freshDefaults())
        s.pausedBundles = ["com.apple.TextEdit", "com.foo.bar"]
        #expect(s.pausedBundles == ["com.apple.TextEdit", "com.foo.bar"])
    }
    @Test func onboardingDefaultsFalse() {
        #expect(AppSettings(defaults: freshDefaults()).onboardingComplete == false)
    }
    @Test func settingsDeepLinkURLs() {
        #expect(SystemSettingsLink.accessibility.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        #expect(SystemSettingsLink.inputMonitoring.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }
    @Test func permissionsAllGrantedLogic() {
        #expect(PermissionsStatus(accessibility: true, inputMonitoring: true).allGranted == true)
        #expect(PermissionsStatus(accessibility: true, inputMonitoring: false).allGranted == false)
    }
}
