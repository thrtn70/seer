import AppKit
import SeerCoordinator
import SeerInference
import SeerAppKit
import SeerModel
import SeerPersonalization
import SeerSupport

/// Accessory agent: status item is always present → if both permissions are granted, build +
/// start the coordinator; otherwise show the onboarding window, which live-polls and auto-
/// proceeds the moment both grants land. No exit(2) on missing permissions — the window runs
/// on every launch when a grant is missing (R11 recovery), then Metal-safe shutdown on quit.
final class AgentDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SuggestionCoordinator?
    private var menuController: MenuController?
    private var onboarding: OnboardingWindow?
    private var settingsWindow: SettingsWindow?
    private var updater: UpdaterController?
    private var modelDownloader: ModelDownloadController?
    /// One quarantine + re-download per run, max. LlamaCppEngine.init throws for several reasons
    /// and only one of them implies bad bytes — "ctx init" is raised *after* the file parsed
    /// successfully — so treating every failure as corruption would re-download 1.1 GB forever on
    /// a machine whose real problem is Metal or memory.
    private var didQuarantineThisRun = false
    /// Set once we stop retrying, so the state callbacks can't re-enter startCoordinator() and
    /// spin on an engine that will never initialise.
    private var modelLoadFailed = false
    private var profileStore: StyleProfileStore?
    private var profileCache: ProfileCache?
    private let settings = AppSettings()
    private let engineName = "llama.cpp (qwen2.5-1.5b)"
    private var signalSources: [DispatchSourceSignal] = []

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
        // Status item is always present, even before permissions are granted.
        let mc = MenuController(settings: settings, engineName: engineName)
        menuController = mc
        // Auto-update is independent of Accessibility/Input-Monitoring — wire it at launch so
        // updates work even while the app is still waiting for permissions.
        let up = UpdaterController()
        updater = up
        mc.updateCheckTarget = up.checkForUpdatesTarget
        mc.updateCheckAction = up.checkForUpdatesAction
        // [weak self]: this delegate strongly holds mc, which holds these closures. main.swift
        // pins the delegate for the process lifetime and NSApp.delegate is unowned(unsafe), so
        // a cycle here would never surface as an observable leak — discipline is the only guard.
        mc.onOpenSettings = { [weak self] in self?.showSettings() }
        mc.onStateMirrored = { [weak self] in self?.settingsWindow?.refresh() }
        mc.setupStatusLine = { [weak self] in self?.setupStatusLine() ?? "Starting…" }
        // The model lives in Application Support, not the bundle (§14). Start fetching it before
        // the permission branch so a ~1 GB transfer overlaps with the user granting permissions —
        // same precedent as wiring Sparkle ahead of the gate.
        if let dir = modelsDirectory() {
            let dl = ModelDownloadController(modelsDirectory: dir)
            modelDownloader = dl
            dl.onStateChange = { [weak self] in
                guard let self else { return }
                self.onboarding?.modelStateChanged()
                self.startCoordinator()          // idempotent; fires when both gates are met
            }
            // Only fetch what we don't already have. Checking resolvability rather than just the
            // Application Support copy keeps `swift run SeerAgent` working off vendor/ instead of
            // re-downloading 1.1 GB the repo already holds.
            if resolvedModelPath() == nil { dl.startIfNeeded() }
        }
        // Built unconditionally, even when everything is already in hand: the recovery paths below
        // and the menu's "Open Setup…" both need something to show, and a window that only exists
        // when setup was incomplete at launch would leave them with nothing.
        let window = OnboardingWindow(onReady: { [weak self] in self?.startCoordinator() })
        window.modelStatus = { [weak self] in
            guard let self else { return .ready }
            // A vendor/ or bundled copy means there is nothing to wait for, even though the
            // downloader (which only knows about Application Support) never ran.
            if self.resolvedModelPath() != nil { return .ready }
            return self.modelDownloader?.state ?? .ready
        }
        window.onRetry = { [weak self] in
            guard let self else { return }
            self.modelLoadFailed = false     // an explicit retry re-arms the start path
            self.modelDownloader?.retry()
        }
        onboarding = window
        mc.onOpenSetup = { [weak self] in self?.onboarding?.show() }
        if isReadyToStart() {
            startCoordinator()
        } else {
            window.show()
        }
    }

    /// Where the model actually is, across all tiers: Application Support (production), the bundle,
    /// or vendor/ (the `swift run SeerAgent` dev flow). nil ⇒ it must be downloaded.
    @MainActor private func resolvedModelPath() -> String? {
        try? ModelLocator.resolve(filename: ModelSpec.filename,
                                  applicationSupportDirectory: modelsDirectory()?.path)
    }

    /// Both gates: permissions AND a model we can actually load from somewhere.
    @MainActor private func isReadyToStart() -> Bool {
        PermissionsStatus.snapshot().allGranted && resolvedModelPath() != nil
    }

    /// Why Seer isn't suggesting yet — `coordinator == nil` alone can no longer say.
    @MainActor private func setupStatusLine() -> String {
        switch modelDownloader?.state {
        case .downloading(_, let detail): return "Downloading model… \(detail)"
        case .verifying:                  return "Verifying model…"
        case .failed:                     return "Model download failed — open Setup"
        default:
            return PermissionsStatus.snapshot().allGranted ? "Starting…" : "Waiting for permissions…"
        }
    }

    /// Build + start the coordinator once permissions are granted AND the model is installed.
    /// Idempotent and order-independent: the granted-at-launch path, the setup-window callback,
    /// and the download-state callback all route here, but it builds at most once, and each
    /// returns harmlessly while the other gate is still outstanding.
    @MainActor private func startCoordinator() {
        guard coordinator == nil, !modelLoadFailed, isReadyToStart() else { return }
        let engine: LlamaCppEngine
        let modelPath: String
        do {
            modelPath = try ModelLocator.resolve(filename: ModelSpec.filename,
                                                 applicationSupportDirectory: modelsDirectory()?.path)
        } catch {
            // Shouldn't happen once the gate is satisfied; re-offer the download rather than die.
            FileHandle.standardError.write(Data("[seer] model missing: \(error)\n".utf8))
            modelDownloader?.startIfNeeded(); onboarding?.show(); return
        }
        do {
            engine = try LlamaCppEngine(modelPath: modelPath)
        } catch {
            // A damaged download must not crash-loop the app on every launch: quarantine it and
            // fetch a fresh copy. A bad bundle/vendor copy is a developer problem and still exits.
            if let dir = modelsDirectory()?.path, modelPath.hasPrefix(dir), !didQuarantineThisRun {
                didQuarantineThisRun = true
                FileHandle.standardError.write(Data(
                    "[seer] model unloadable, quarantining: \(error)\n".utf8))
                modelDownloader?.quarantineAndRetry(); onboarding?.show(); return
            }
            if let dir = modelsDirectory()?.path, modelPath.hasPrefix(dir) {
                // Second failure on a freshly downloaded, checksum-verified copy. The bytes match
                // ModelSpec.sha256, so re-downloading would fetch byte-identical data and fail
                // identically — the cause is the environment (Metal/GPU, memory, a llama.cpp/GGUF
                // mismatch), not the file. Stop, and say so, instead of looping on 1.1 GB.
                modelLoadFailed = true
                FileHandle.standardError.write(Data(
                    "[seer] model still unloadable after re-download: \(error)\n".utf8))
                modelDownloader?.reportUnloadable(
                    "The model downloaded correctly but could not be loaded — this looks like a system problem, not a bad download.")
                onboarding?.show(); return
            }
            FileHandle.standardError.write(Data("[seer] FAILED to load model: \(error)\n".utf8)); exit(2)
        }
        // §7 personalization: cache is the hot path's sync read; the store owns all I/O off
        // main. Keychain resolution + vault load run inside the actor on first use, so a
        // keychain prompt can never block the UI.
        let cache = ProfileCache()
        profileCache = cache
        let store = StyleProfileStore(vault: personalizationVault(),
                                      keyProvider: KeychainKeyProvider(),
                                      overrides: settings.toneOverrides,
                                      publish: { cache.publish($0) })
        profileStore = store
        Task { await store.loadAndPublish() }
        let c = SuggestionCoordinator(engine: engine, profileCache: cache)
        coordinator = c
        // Must stay ahead of attach(): apply() fires onStateChanged per knob, and an attached
        // MenuController would persist mid-replay (see SuggestionCoordinator.apply).
        c.apply(CoordinatorTuning(settings))
        // Fire-and-forget (§4 step 10): the key-tap path only spawns the Task; the actor does
        // the reduce/persist/publish off the hot path.
        c.onLearn = { [weak self] sample in
            guard let store = self?.profileStore else { return }
            Task { await store.record(sample) }
        }
        menuController?.attach(c)
        Task { @MainActor in
            await c.start()
            if c.tapIsRunning {
                print("[seer] Ready. Type in any text field; Tab accepts a word, ⇧Tab the line, Esc dismisses. Ctrl-C to quit.")
            } else {
                FileHandle.standardError.write(Data("[seer] keystroke tap failed to start — check Input Monitoring.\n".utf8))
            }
        }
        // attach() deliberately bypasses stateDidChange(), so the nil-coordinator → attached
        // transition fires no mirror hook. Settings can be open already (the Settings… item
        // lives outside the permission gate), so nudge it here rather than routing attach()
        // through stateDidChange() and dragging persistence into that path.
        settingsWindow?.refresh()
    }

    @MainActor private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(settings: settings, engineName: engineName,
                                            coordinator: { [weak self] in self?.coordinator },
                                            profileStore: { [weak self] in self?.profileStore },
                                            profileCache: { [weak self] in self?.profileCache })
        }
        settingsWindow?.show()
    }

    /// ~/Library/Application Support/Seer/personalization.db (§7.2). nil (no home dir /
    /// creation failure) ⇒ the store runs memory-only — never block suggestions on storage.
    /// ~/Library/Application Support/Seer/models/ — sibling of personalization.db (§14). The
    /// model lives outside the .app so a Sparkle update ships tens of MB instead of ~1 GB, and
    /// so an update never re-downloads a model the user already has. nil (no home dir / creation
    /// failure) ⇒ no download is possible; ModelLocator still finds a bundled or dev copy.
    private func modelsDirectory() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("Seer", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            FileHandle.standardError.write(Data(
                "[seer] Application Support unavailable (\(error)) — cannot install the model\n".utf8))
            return nil
        }
        return dir
    }

    private func personalizationVault() -> PersonalizationVault? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("Seer", isDirectory: true)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            FileHandle.standardError.write(Data(
                "[seer] Application Support unavailable (\(error)) — personalization is memory-only\n".utf8))
            return nil
        }
        return PersonalizationVault(fileURL: dir.appendingPathComponent("personalization.db"))
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
