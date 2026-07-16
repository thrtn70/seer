import Testing
@testable import SeerModel

@Suite struct AppPolicyTests {
    @Test func enabledAndNotPausedSuggests() {
        #expect(AppPolicy.shouldSuggest(enabled: true, pausedBundles: [], bundleID: "com.apple.TextEdit") == true)
    }
    @Test func disabledNeverSuggests() {
        #expect(AppPolicy.shouldSuggest(enabled: false, pausedBundles: [], bundleID: "com.apple.TextEdit") == false)
    }
    @Test func pausedBundleDoesNotSuggest() {
        #expect(AppPolicy.shouldSuggest(enabled: true, pausedBundles: ["com.apple.TextEdit"], bundleID: "com.apple.TextEdit") == false)
    }
    @Test func otherBundleStillSuggests() {
        #expect(AppPolicy.shouldSuggest(enabled: true, pausedBundles: ["com.foo.bar"], bundleID: "com.apple.TextEdit") == true)
    }
}
