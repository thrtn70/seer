import Testing
import Foundation
import CryptoKit
@testable import SeerSupport

@Suite struct ModelInstallerTests {
    /// sha256("hello") — a known-good expectation.
    private let helloSHA = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seer.installer.\(UInt64.random(in: 0...(.max)))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func installsWhenChecksumMatches() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let temp = dir.appendingPathComponent("staged")
        let dest = dir.appendingPathComponent("model.gguf")
        try Data("hello".utf8).write(to: temp)

        try ModelInstaller.verifyAndInstall(temp: temp, expectedSHA256: helloSHA, destination: dest)

        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: temp.path))   // moved, not copied
        #expect(try String(contentsOf: dest, encoding: .utf8) == "hello")
    }

    @Test func rejectsAndInstallsNothingWhenChecksumDiffers() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let temp = dir.appendingPathComponent("staged")
        let dest = dir.appendingPathComponent("model.gguf")
        try Data("tampered".utf8).write(to: temp)

        #expect(throws: ModelInstallError.checksumMismatch) {
            try ModelInstaller.verifyAndInstall(temp: temp, expectedSHA256: helloSHA, destination: dest)
        }
        // The whole point: a corrupt download must never become the installed model.
        #expect(!FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: temp.path))   // staged copy discarded
    }

    /// A mismatched download must not clobber a model that is already installed and good.
    @Test func leavesAnExistingGoodModelIntactOnMismatch() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let temp = dir.appendingPathComponent("staged")
        let dest = dir.appendingPathComponent("model.gguf")
        try Data("good-existing".utf8).write(to: dest)
        try Data("tampered".utf8).write(to: temp)

        #expect(throws: ModelInstallError.checksumMismatch) {
            try ModelInstaller.verifyAndInstall(temp: temp, expectedSHA256: helloSHA, destination: dest)
        }
        #expect(try String(contentsOf: dest, encoding: .utf8) == "good-existing")
    }

    @Test func replacesAnExistingModelWhenChecksumMatches() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let temp = dir.appendingPathComponent("staged")
        let dest = dir.appendingPathComponent("model.gguf")
        try Data("stale".utf8).write(to: dest)
        try Data("hello".utf8).write(to: temp)

        try ModelInstaller.verifyAndInstall(temp: temp, expectedSHA256: helloSHA, destination: dest)
        #expect(try String(contentsOf: dest, encoding: .utf8) == "hello")
    }

    @Test func quarantineRenamesTheBadModel() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = dir.appendingPathComponent("model.gguf")
        try Data("junk".utf8).write(to: model)

        try ModelInstaller.quarantine(model)

        #expect(!FileManager.default.fileExists(atPath: model.path))
        #expect(FileManager.default.fileExists(atPath: model.appendingPathExtension("corrupt").path))
    }

    /// Quarantining twice must not fail on the leftover `.corrupt` from the first time.
    @Test func quarantineOverwritesAPreviousCorruptFile() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = dir.appendingPathComponent("model.gguf")
        try Data("first".utf8).write(to: model)
        try ModelInstaller.quarantine(model)
        try Data("second".utf8).write(to: model)

        try ModelInstaller.quarantine(model)

        #expect(try String(contentsOf: model.appendingPathExtension("corrupt"),
                           encoding: .utf8) == "second")
    }

    /// The model is ~1 GB, so hashing must stream. Uses a size that is not a chunk multiple.
    @Test func hashesLargeInputInChunks() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("big")
        let blob = Data(repeating: 0xAB, count: 5 * 1024 * 1024 + 7)
        try blob.write(to: file)
        let expected = SHA256.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        #expect(try ModelInstaller.sha256(ofFileAt: file) == expected)
    }
}
