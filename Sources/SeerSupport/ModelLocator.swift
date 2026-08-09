import Foundation

/// Thrown when the model file cannot be located in any known location.
public enum ModelLocatorError: Error, Equatable {
    case notFound(String)
}

/// Resolves a path to the GGUF model.
///
/// Resolution order:
/// 1. Application Support — `<applicationSupportDirectory>/<filename>`, where the app downloads
///    the model on first run (§14). `nil` skips this tier entirely, which is what SeerBench and
///    the probes want: they must resolve `vendor/` deterministically.
/// 2. `Bundle.main` resource — a bundled build. The model no longer ships this way, but a bundle
///    that does carry one must still win over the dev copy.
/// 3. Dev fallback — `<devDirectory>/<filename>` (e.g. `vendor/…` relative to the repo
///    root when running via `swift run`).
///
/// Pure and dependency-free (no `llama`, no AppKit). The bundle lookup is injected as a
/// closure so it is fully unit-testable without a real bundle on disk.
public enum ModelLocator {
    public static func resolve(
        filename: String,
        applicationSupportDirectory: String? = nil,
        bundleLookup: (_ name: String, _ ext: String?) -> URL? = { Bundle.main.url(forResource: $0, withExtension: $1) },
        devDirectory: String = "vendor",
        fileManager: FileManager = .default
    ) throws -> String {
        if let appSupport = applicationSupportDirectory {
            let path = (appSupport as NSString).appendingPathComponent(filename)
            if fileManager.fileExists(atPath: path) { return path }
        }
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        if let url = bundleLookup(name, ext.isEmpty ? nil : ext) {
            return url.path
        }
        let devPath = (devDirectory as NSString).appendingPathComponent(filename)
        if fileManager.fileExists(atPath: devPath) {
            return devPath
        }
        throw ModelLocatorError.notFound(filename)
    }
}
