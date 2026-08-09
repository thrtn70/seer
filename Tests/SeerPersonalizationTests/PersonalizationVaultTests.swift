import Testing
import Foundation
import CryptoKit
@testable import SeerPersonalization

private func tempVault() -> (PersonalizationVault, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("seer-vault-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("personalization.db")
    return (PersonalizationVault(fileURL: url), url)
}
private let key = SymmetricKey(size: .bits256)

private func sampleProfile() -> StyleProfile {
    ProfileReducer.reduce(.empty, sample: AcceptedSample(
        bundleID: "com.apple.TextEdit", focusedSubrole: nil, completion: "thanks for the update",
        beforeCaret: "secret before text", timestamp: Date(timeIntervalSince1970: 100)))
}

@Suite struct PersonalizationVaultTests {
    @Test func roundTripsProfile() throws {
        let (vault, _) = tempVault()
        let profile = sampleProfile()
        try vault.save(profile, key: key)
        #expect(vault.load(key: key) == .profile(profile))
    }
    @Test func missingFileIsAbsent() {
        let (vault, _) = tempVault()
        #expect(vault.load(key: key) == .absent)
    }
    @Test func fileStartsWithMagicAndVersionAndHidesPlaintext() throws {
        let (vault, url) = tempVault()
        try vault.save(sampleProfile(), key: key)
        let blob = try Data(contentsOf: url)
        #expect(Array(blob.prefix(4)) == Array("SEER".utf8))
        #expect(blob[4] == PersonalizationVault.formatVersion)
        // Encrypted at rest (§7.8): no plaintext of the accepted text or context survives.
        let body = String(decoding: blob, as: UTF8.self)
        #expect(!body.contains("thanks for the update"))
        #expect(!body.contains("secret before text"))
    }
    @Test func garbageFileIsCorruptAndMovedAside() throws {
        let (vault, url) = tempVault()
        try Data("not a vault at all".utf8).write(to: url)
        #expect(vault.load(key: key) == .corrupt)
        #expect(!FileManager.default.fileExists(atPath: url.path))          // moved away
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".corrupt")
        #expect(FileManager.default.fileExists(atPath: aside.path))          // preserved aside
    }
    @Test func wrongKeyIsCorrupt() throws {
        let (vault, _) = tempVault()
        try vault.save(sampleProfile(), key: key)
        #expect(vault.load(key: SymmetricKey(size: .bits256)) == .corrupt)
    }
    @Test func wrongFormatVersionIsCorrupt() throws {
        let (vault, url) = tempVault()
        try vault.save(sampleProfile(), key: key)
        var blob = try Data(contentsOf: url)
        blob[4] = PersonalizationVault.formatVersion &+ 1
        try blob.write(to: url)
        #expect(vault.load(key: key) == .corrupt)
    }
    @Test func saveOverwritesAtomically() throws {
        let (vault, _) = tempVault()
        try vault.save(sampleProfile(), key: key)
        let bigger = ProfileReducer.reduce(sampleProfile(), sample: AcceptedSample(
            bundleID: "app.two", focusedSubrole: nil, completion: "will do",
            beforeCaret: "b", timestamp: Date(timeIntervalSince1970: 200)))
        try vault.save(bigger, key: key)
        #expect(vault.load(key: key) == .profile(bigger))
    }
    @Test func truncatedSealedBoxIsCorruptNotCrash() throws {
        // Valid magic+version, but the GCM box is chopped — the `try? SealedBox(combined:)` /
        // `try? open` chain must return .corrupt, never crash (§7.6 never-block).
        let (vault, url) = tempVault()
        try vault.save(sampleProfile(), key: key)
        let blob = try Data(contentsOf: url)
        try blob.prefix(blob.count - 8).write(to: url)
        #expect(vault.load(key: key) == .corrupt)
    }
    @Test func decryptableButNonJSONPayloadIsCorruptNotCrash() throws {
        // Valid envelope, real key, decrypts fine — but the plaintext isn't StyleProfile JSON
        // (e.g. a future schema drift without a version bump). Must be .corrupt, not a `try!` crash.
        let (vault, url) = tempVault()
        let sealed = try AES.GCM.seal(Data("not a profile at all".utf8), using: key)
        var blob = Data("SEER".utf8)
        blob.append(PersonalizationVault.formatVersion)
        blob.append(sealed.combined!)
        try blob.write(to: url)
        #expect(vault.load(key: key) == .corrupt)
    }
}
