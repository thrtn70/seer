import AppKit
import SeerCoordinator
import SeerAppKit

/// The menu-bar status item: global on/off, pause-for-current-app, status, quit.
/// The status item is created at launch and persists regardless of permission state; the
/// coordinator is attached later (once permissions are granted) via `attach(_:)`.
@MainActor
final class MenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var coordinator: SuggestionCoordinator?
    private var settings: AppSettings
    private let engineName: String

    init(settings: AppSettings, engineName: String) {
        self.settings = settings; self.engineName = engineName
        super.init()
        statusItem.button?.title = "S"   // placeholder glyph; an icon is a later polish
        let menu = NSMenu()
        menu.delegate = self             // rebuild on open so checkmarks/status are fresh
        statusItem.menu = menu
    }

    /// Attach the coordinator once it has been built (permissions granted). Wires the
    /// state-changed callback so menu toggles and the panic hotkey persist their effect.
    func attach(_ coordinator: SuggestionCoordinator) {
        self.coordinator = coordinator
        coordinator.onStateChanged = { [weak self] in self?.persistState() }
    }

    private func persistState() {
        guard let coordinator else { return }
        settings.enabled = coordinator.isEnabled
        settings.pausedBundles = coordinator.pausedBundles
    }
    private func currentBundleID() -> String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    @objc private func toggleEnabled() {
        guard let coordinator else { return }
        coordinator.setEnabled(!coordinator.isEnabled)   // fires onStateChanged → persistState
    }
    @objc private func togglePauseCurrent() {
        guard let coordinator, let b = currentBundleID() else { return }
        coordinator.setPaused(!coordinator.isPaused(bundleID: b), bundleID: b)   // fires onStateChanged → persistState
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension MenuController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let coordinator {
            let onOff = NSMenuItem(title: "Seer Suggestions", action: #selector(toggleEnabled), keyEquivalent: "")
            onOff.target = self; onOff.state = coordinator.isEnabled ? .on : .off
            menu.addItem(onOff)
            if let app = NSWorkspace.shared.frontmostApplication, let b = app.bundleIdentifier {
                let name = app.localizedName ?? b
                let pause = NSMenuItem(title: "Pause for \(name)", action: #selector(togglePauseCurrent), keyEquivalent: "")
                pause.target = self; pause.state = coordinator.isPaused(bundleID: b) ? .on : .off
                menu.addItem(pause)
            }
        } else {
            menu.addItem(disabledItem("Waiting for permissions…"))
        }
        menu.addItem(.separator())
        let perms = PermissionsStatus.snapshot()
        menu.addItem(disabledItem("Engine: \(engineName)"))
        menu.addItem(disabledItem("Accessibility: \(perms.accessibility ? "✓" : "✗")   Input Monitoring: \(perms.inputMonitoring ? "✓" : "✗")"))
        menu.addItem(disabledItem("Panic: ⌃⌥⌘."))
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Seer", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    private func disabledItem(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""); i.isEnabled = false; return i
    }
}
