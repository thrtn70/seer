import Foundation
import CryptoKit

public enum ModelInstallError: Error, Equatable {
    case checksumMismatch
}

/// Verifies a downloaded model and moves it into place, or quarantines one that turned out to be
/// unloadable. Pure file/crypto work — no networking, no AppKit — so it is unit-testable, and the
/// download layer above it has no code path that can publish a model that was never checked.
public enum ModelInstaller {
    /// 1 MiB chunks: the model is ~1 GB, so it must never be read into memory whole.
    private static let chunkSize = 1 << 20

    public static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Verify `temp` against `expectedSHA256`, then atomically move it to `destination`.
    ///
    /// On mismatch the staged file is deleted and `destination` is left exactly as it was — a bad
    /// download must never become the installed model, must not clobber a good existing one, and
    /// must not linger to be retried into.
    public static func verifyAndInstall(temp: URL, expectedSHA256: String, destination: URL) throws {
        let actual = try sha256(ofFileAt: temp)
        guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            try? FileManager.default.removeItem(at: temp)
            throw ModelInstallError.checksumMismatch
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: destination)
        }
    }

    /// Rename a model the engine refused to load, so the next launch re-downloads instead of
    /// crash-looping on it. Mirrors PersonalizationVault.moveAside()'s `.corrupt` convention.
    /// Any previous `.corrupt` is replaced — the newest failure is the informative one.
    public static func quarantine(_ url: URL) throws {
        let corrupt = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: corrupt)
        try FileManager.default.moveItem(at: url, to: corrupt)
    }
}
