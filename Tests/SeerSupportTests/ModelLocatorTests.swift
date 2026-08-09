import Testing
import Foundation
@testable import SeerSupport

@Suite struct ModelLocatorTests {
    @Test func prefersBundleResource() throws {
        let bundleURL = URL(fileURLWithPath: "/bundle/Resources/model.gguf")
        let resolved = try ModelLocator.resolve(
            filename: "model.gguf",
            bundleLookup: { name, ext in
                #expect(name == "model")
                #expect(ext == "gguf")
                return bundleURL
            },
            devDirectory: "/should/not/be/used")
        #expect(resolved == bundleURL.path)
    }

    @Test func splitsDottedModelFilename() throws {
        let resolved = try ModelLocator.resolve(
            filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            bundleLookup: { name, ext in
                #expect(name == "qwen2.5-1.5b-instruct-q4_k_m")
                #expect(ext == "gguf")
                return URL(fileURLWithPath: "/b/qwen2.5-1.5b-instruct-q4_k_m.gguf")
            },
            devDirectory: "/unused")
        #expect(resolved == "/b/qwen2.5-1.5b-instruct-q4_k_m.gguf")
    }

    @Test func fallsBackToDevDirectoryWhenNotInBundle() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seer.modeltest.\(UInt64.random(in: 0...(.max)))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let modelPath = dir.appendingPathComponent("model.gguf").path
        FileManager.default.createFile(atPath: modelPath, contents: Data("x".utf8))

        let resolved = try ModelLocator.resolve(
            filename: "model.gguf",
            bundleLookup: { _, _ in nil },          // not in bundle → fall back
            devDirectory: dir.path)
        #expect(resolved == modelPath)
    }

    @Test func prefersApplicationSupportOverBundle() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seer.modeltest.\(UInt64.random(in: 0...(.max)))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let modelPath = dir.appendingPathComponent("model.gguf").path
        FileManager.default.createFile(atPath: modelPath, contents: Data("x".utf8))

        let resolved = try ModelLocator.resolve(
            filename: "model.gguf",
            applicationSupportDirectory: dir.path,
            bundleLookup: { _, _ in URL(fileURLWithPath: "/bundle/model.gguf") },   // must lose
            devDirectory: "/should/not/be/used")
        #expect(resolved == modelPath)
    }

    @Test func fallsThroughWhenApplicationSupportIsEmpty() throws {
        let bundleURL = URL(fileURLWithPath: "/bundle/Resources/model.gguf")
        let resolved = try ModelLocator.resolve(
            filename: "model.gguf",
            applicationSupportDirectory: "/nonexistent-\(UInt64.random(in: 0...(.max)))",
            bundleLookup: { _, _ in bundleURL },
            devDirectory: "/unused")
        #expect(resolved == bundleURL.path)
    }

    @Test func throwsNotFoundWhenMissingEverywhere() {
        #expect(throws: ModelLocatorError.notFound("model.gguf")) {
            try ModelLocator.resolve(
                filename: "model.gguf",
                bundleLookup: { _, _ in nil },
                devDirectory: "/nonexistent-\(UInt64.random(in: 0...(.max)))")
        }
    }
}
