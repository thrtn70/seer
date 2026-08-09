import Testing
import Foundation
@testable import SeerSupport

@Suite struct ModelSpecTests {
    /// Locates the repo root from this file's own path, so the test works regardless of CWD.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)          // Tests/SeerSupportTests/ModelSpecTests.swift
            .deletingLastPathComponent()          // SeerSupportTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
    }

    @Test func filenameMatchesTheURL() {
        #expect(ModelSpec.sourceURL.lastPathComponent == ModelSpec.filename)
    }

    @Test func checksumIsALowercaseSHA256() {
        #expect(ModelSpec.sha256.count == 64)
        #expect(ModelSpec.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    /// Drift guard: the shell fetcher and the Swift constants describe the same artifact.
    /// Without this, hardening the script or bumping the model in one place silently diverges
    /// the dev path (vendor/) from what the app downloads and verifies at runtime.
    @Test func fetchScriptPinsTheSameArtifact() throws {
        let script = try String(contentsOf: repoRoot.appendingPathComponent("scripts/fetch-model.sh"),
                                encoding: .utf8)
        // Match the ASSIGNMENTS, not just the values: a substring check would pass while the hash
        // sat in a comment and a different one was actually assigned to EXPECTED_SHA256.
        #expect(script.contains("EXPECTED_SHA256=\"\(ModelSpec.sha256)\""),
                "fetch-model.sh must assign ModelSpec.sha256 to EXPECTED_SHA256")
        #expect(script.contains("MODEL_URL=\"\(ModelSpec.sourceURL.absoluteString)\""),
                "fetch-model.sh must assign ModelSpec.sourceURL to MODEL_URL")
    }
}
