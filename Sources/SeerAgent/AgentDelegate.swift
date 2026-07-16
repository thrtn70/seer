import AppKit
import SeerCoordinator
import SeerInference
import SeerAppKit
import SeerSupport

/// Accessory agent: status item is always present → if both permissions are granted, build +
/// start the coordinator; otherwise show the onboarding window, which live-polls and auto-
/// proceeds the moment both grants land. No exit(2) on missing permissions — the window runs
/// on every launch when a grant is missing (R11 recovery), then Metal-safe shutdown on quit.
final class AgentDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SuggestionCoordinator?
    private var menuController: MenuController?
    private var onboarding: OnboardingWindow?
    private let settings = AppSettings()
    private let engineName = "llama.cpp (qwen2.5-1.5b)"
    private var signalSources: [DispatchSourceSignal] = []

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
        // Status item is always present, even before permissions are granted.
        let mc = MenuController(settings: settings, engineName: engineName)
        menuController = mc
        if PermissionsStatus.snapshot().allGranted {
            startCoordinator()
        } else {
            let window = OnboardingWindow(onGranted: { [weak self] in self?.startCoordinator() })
            onboarding = window
            window.show()
        }
    }

    /// Build + start the coordinator once permissions are granted. Idempotent: both the
    /// granted-at-launch path and the onboarding callback route here, but it builds at most once.
    @MainActor private func startCoordinator() {
        guard coordinator == nil else { return }
        let engine: LlamaCppEngine
        do {
            let modelPath = try ModelLocator.resolve(filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf")
            engine = try LlamaCppEngine(modelPath: modelPath)
        } catch {
            FileHandle.standardError.write(Data("[seer] FAILED to load model: \(error)\n".utf8)); exit(2)
        }
        let c = SuggestionCoordinator(engine: engine)
        coordinator = c
        c.setEnabled(settings.enabled)
        for bundle in settings.pausedBundles { c.setPaused(true, bundleID: bundle) }
        menuController?.attach(c)
        Task { @MainActor in
            await c.start()
            if c.tapIsRunning {
                print("[seer] Ready. Type in any text field; Tab accepts a word, ⇧Tab the line, Esc dismisses. Ctrl-C to quit.")
            } else {
                FileHandle.standardError.write(Data("[seer] keystroke tap failed to start — check Input Monitoring.\n".utf8))
            }
        }
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }

    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.coordinator?.shutdown() }
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }
}
