import Testing
import CryptoKit
@testable import SeerPersonalization

@Suite struct KeyProvidingTests {
    @Test func inMemoryProviderRoundTripsKey() {
        let key = SymmetricKey(size: .bits256)
        let provider = InMemoryKeyProvider(key: key)
        #expect(provider.loadOrCreateKey() == key)
    }
    @Test func nilKeyModelsKeychainUnavailable() {
        #expect(InMemoryKeyProvider(key: nil).loadOrCreateKey() == nil)
    }
}
