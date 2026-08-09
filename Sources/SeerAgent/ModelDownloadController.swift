import AppKit
import SeerSupport

/// Downloads the GGUF into Application Support on first run (§14), publishing state for the setup
/// window and the menu. Modelled on the StyleProfileStore → ProfileCache publish shape: this owns
/// the state, callers read it synchronously on the main actor and re-render on `onStateChange`.
@MainActor
final class ModelDownloadController: NSObject {
    enum State {
        case idle
        case downloading(fraction: Double?, detail: String)
        case verifying
        case ready
        case failed(String)

        var isReady: Bool { if case .ready = self { return true }; return false }
    }

    private(set) var state: State = .idle { didSet { onStateChange?() } }
    var onStateChange: (() -> Void)?

    private let destination: URL
    /// URLSession deletes its temp file as soon as the delegate callback returns, so the download
    /// is moved here synchronously and hashed afterwards.
    private let staging: URL
    private var session: URLSession!
    private var task: URLSessionDownloadTask?

    init(modelsDirectory: URL) {
        self.destination = modelsDirectory.appendingPathComponent(ModelSpec.filename)
        self.staging = modelsDirectory.appendingPathComponent(ModelSpec.filename + ".download")
        super.init()
        // A staging file left by a previous run is meaningless (no resume data is kept) and would
        // otherwise sit there wasting ~1 GB for the life of the install.
        try? FileManager.default.removeItem(at: staging)
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    var isModelInstalled: Bool { FileManager.default.fileExists(atPath: destination.path) }

    /// Idempotent: a second call while a download is in flight is ignored.
    func startIfNeeded() {
        if isModelInstalled { state = .ready; return }
        guard task == nil else { return }
        state = .downloading(fraction: 0, detail: "Starting…")
        let t = session.downloadTask(with: ModelSpec.sourceURL)
        task = t
        t.resume()
    }

    /// Retry after a failure — clears the failed state and starts over.
    func retry() {
        task = nil
        try? FileManager.default.removeItem(at: staging)
        startIfNeeded()
    }

    /// The engine could not load the installed model: quarantine it and download a fresh copy,
    /// rather than letting every launch crash-loop on the same bad file. Callers must bound how
    /// often they invoke this — a re-download is only worth attempting once per run.
    func quarantineAndRetry() {
        try? ModelInstaller.quarantine(destination)
        state = .failed("The model file was damaged and has been removed.")
        retry()
    }

    /// Give up on loading: the file is present and passes its checksum but the engine still can't
    /// use it, so another download would fetch byte-identical data. Reports without retrying.
    func reportUnloadable(_ message: String) {
        task = nil
        state = .failed(message)
    }
}

extension ModelDownloadController: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        // The server may not report a length; fall back to the known size so the bar still moves.
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : ModelSpec.expectedByteCount
        let fraction = ModelDownloadProgress.fraction(completed: totalBytesWritten, total: total)
        let detail = ModelDownloadProgress.describe(completed: totalBytesWritten, total: total)
        Task { @MainActor [weak self] in
            self?.state = .downloading(fraction: fraction, detail: detail)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // MUST be synchronous: URLSession deletes `location` the moment this method returns.
        // Anything async here — including hopping to the main actor first — loses the file.
        let staged = staging
        let http = downloadTask.response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        var failure: String?
        if (200..<300).contains(status) {
            do {
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.moveItem(at: location, to: staged)
            } catch {
                failure = "Could not save the download: \(error.localizedDescription)"
            }
        } else {
            // A 404/500 body downloads perfectly happily; only the status distinguishes it.
            failure = "Download failed (HTTP \(status))."
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let failure { self.finishFailed(failure); return }
            await self.verifyAndInstallStaged()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error else { return }   // the success path is handled in didFinishDownloadingTo
        Task { @MainActor [weak self] in
            self?.finishFailed("Download failed: \(error.localizedDescription)")
        }
    }
}

private extension ModelDownloadController {
    func finishFailed(_ message: String) {
        task = nil
        try? FileManager.default.removeItem(at: staging)
        state = .failed(message)
    }

    /// Hash + install off the main actor: SHA-256 over ~1 GB would otherwise freeze the UI.
    func verifyAndInstallStaged() async {
        state = .verifying
        let staged = staging, dest = destination
        do {
            try await Task.detached(priority: .utility) {
                try ModelInstaller.verifyAndInstall(temp: staged,
                                                    expectedSHA256: ModelSpec.sha256,
                                                    destination: dest)
            }.value
            task = nil
            state = .ready
        } catch ModelInstallError.checksumMismatch {
            finishFailed("The downloaded model was corrupt (checksum mismatch).")
        } catch {
            finishFailed("Could not install the model: \(error.localizedDescription)")
        }
    }
}
