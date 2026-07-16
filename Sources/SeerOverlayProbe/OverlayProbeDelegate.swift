import AppKit

/// Boots the probe and guarantees `engine.shutdown()` runs exactly once before exit
/// (Ctrl-C / SIGTERM bypass deinit; Metal teardown SIGABRTs if shutdown is skipped).
final class OverlayProbeDelegate: NSObject, NSApplicationDelegate {
    private var probe: OverlayProbe?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = CommandLine.arguments.contains("--demo")
        let pill = CommandLine.arguments.contains("--pill")
        let p = OverlayProbe(demo: demo, pill: pill)
        probe = p
        installSignalHandlers()
        p.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { probe?.shutdown() }
    }

    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)   // disable default terminate so the DispatchSource fires
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.probe?.shutdown() }
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }
}
