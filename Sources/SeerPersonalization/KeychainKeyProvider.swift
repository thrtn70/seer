import CryptoKit
import Foundation
import Security

/// Real key storage: a generic-password item in the LEGACY file keychain. The spec's
/// kSecAttrAccessibleWhenUnlockedThisDeviceOnly is unattainable here — the data-protection
/// keychain (kSecUseDataProtectionKeychain) requires an application-identifier entitlement a
/// self-signed app cannot hold (errSecMissingEntitlement) — recorded deviation, parent spec
/// §7.2. On the legacy keychain the ACL binds to the code signature; the packaged app
/// (stable SeerCodeSign cert) prompts once. Every failure path returns nil (memory-only
/// session) and logs to stderr — called once per launch from the store's load.
public struct KeychainKeyProvider: KeyProviding {
    public static let service = "app.seer.agent"
    public static let account = "personalization-key"
    public init() {}

    public func loadOrCreateKey() -> SymmetricKey? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecReturnData: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecSuccess, let data = out as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { return failed("read", status) }
        let key = SymmetricKey(size: .bits256)
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecValueData: key.withUnsafeBytes { Data($0) },
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { return failed("create", addStatus) }
        return key
    }

    private func failed(_ op: String, _ status: OSStatus) -> SymmetricKey? {
        FileHandle.standardError.write(Data(
            "[seer] personalization key \(op) failed (\(status)) — memory-only session\n".utf8))
        return nil
    }
}
