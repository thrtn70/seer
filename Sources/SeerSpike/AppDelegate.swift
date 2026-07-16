import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SpikeCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let ax = Permissions.hasAccessibility(prompt: true)
        Permissions.requestInputMonitoring()
        let im = Permissions.hasInputMonitoring()
        NSLog("[seer] accessibility=%@ inputMonitoring=%@", ax ? "yes" : "no", im ? "yes" : "no")
        guard ax, im else {
            NSLog("[seer] grant Accessibility + Input Monitoring, then relaunch")
            return
        }
        let c = SpikeCoordinator()
        c.start()
        coordinator = c
    }
}
