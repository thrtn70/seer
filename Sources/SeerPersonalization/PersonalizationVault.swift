import CryptoKit
import Foundation

/// Sealed-file envelope (§7.2 as amended): 4-byte magic "SEER" + 1-byte format version +
/// AES.GCM combined box over sorted-keys JSON of StyleProfile. Atomic replace on save;
/// any load failure moves the file aside (".corrupt") and reports fresh — never crash,
/// never block suggestions (§7.6).
public struct PersonalizationVault: Sendable {
    public static let formatVersion: UInt8 = 1
    private static let magic = Array("SEER".utf8)

    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public enum LoadResult: Equatable {
        case profile(StyleProfile)
        case absent
        case corrupt
    }

    public func save(_ profile: StyleProfile, key: SymmetricKey) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = try encoder.encode(profile)
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { throw CocoaError(.fileWriteUnknown) }
        var blob = Data(Self.magic)
        blob.append(Self.formatVersion)
        blob.append(combined)
        let tmp = fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.lastPathComponent + ".tmp")
        try blob.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }

    public func load(key: SymmetricKey) -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .absent }
        let headerLength = Self.magic.count + 1
        guard let blob = try? Data(contentsOf: fileURL),
              blob.count > headerLength,
              Array(blob.prefix(Self.magic.count)) == Self.magic,
              blob[Self.magic.count] == Self.formatVersion,
              let box = try? AES.GCM.SealedBox(combined: blob.dropFirst(headerLength)),
              let plain = try? AES.GCM.open(box, using: key),
              let profile = try? JSONDecoder().decode(StyleProfile.self, from: plain)
        else {
            moveAside()
            return .corrupt
        }
        return .profile(profile)
    }

    private func moveAside() {
        let aside = fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.lastPathComponent + ".corrupt")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: fileURL, to: aside)
    }

    /// Best-effort removal of the artifacts the vault itself can create (`.corrupt` from
    /// moveAside, `.tmp` from an interrupted save). Called by the global reset (§7.8
    /// amendment): the privacy escape hatch must not leave decryptable ciphertext behind.
    public func removeSiblings() {
        for suffix in [".corrupt", ".tmp"] {
            let url = fileURL.deletingLastPathComponent()
                .appendingPathComponent(fileURL.lastPathComponent + suffix)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
