import CryptoKit
import Foundation

/// Supplies the vault key. nil ⇒ Keychain unavailable — the store runs memory-only for the
/// session (keeps learning, never persists, never blocks suggestions). Ad-hoc dev binaries
/// (`swift build`) hit this on every rebuild: the legacy-keychain ACL binds to the cdhash.
public protocol KeyProviding: Sendable {
    func loadOrCreateKey() -> SymmetricKey?
}

/// Test/dev provider: a fixed key, or nil to model an unavailable Keychain.
public struct InMemoryKeyProvider: KeyProviding {
    private let keyData: Data?
    public init(key: SymmetricKey?) {
        self.keyData = key.map { k in k.withUnsafeBytes { Data($0) } }
    }
    public func loadOrCreateKey() -> SymmetricKey? { keyData.map(SymmetricKey.init(data:)) }
}
