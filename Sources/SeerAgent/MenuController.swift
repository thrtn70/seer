import AppKit
import SeerCoordinator
import SeerAppKit

/// The menu-bar status item: global on/off, pause-for-current-app, stats, status, quit.
/// The status item is created at launch and persists regardless of permission state; the
/// coordinator is attached later (once permissions are granted) via `attach(_:)`.
@MainActor
final class MenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var coordinator: SuggestionCoordinator?
    private var settings: AppSettings
    private let engineName: String
    private let stats: StatsStore

    /// Invoked when the user picks "Settings…" — AgentDelegate owns/creates the window.
    var onOpenSettings: (() -> Void)?
    /// Invoked after every coordinator state change has been persisted, so an open
    /// Settings window can mirror it. Deliberately separate from the coordinator's
    /// single-slot onStateChanged, which this controller owns (persist + icon).
    var onStateMirrored: (() -> Void)?
    /// "Check for Updates…" target/action, handed over by AgentDelegate as an opaque pair so
    /// this file never imports Sparkle. The target (Sparkle's updater controller) implements
    /// NSMenuValidation, so the item enables/disables itself during an in-flight check.
    var updateCheckTarget: AnyObject?
    var updateCheckAction: Selector?
    /// Why Seer isn't suggesting yet. `coordinator == nil` alone can no longer say — it now means
    /// "missing permissions" OR "model still downloading" — so AgentDelegate supplies the reason
    /// and this file stays free of model/download types.
    var setupStatusLine: (() -> String)?
    /// Re-opens the setup window. Without this the status line can say "open Setup" while nothing
    /// in the UI can actually open it: dismissing the window after a failed download would strand
    /// the user with an unreachable Retry button until they quit and relaunch.
    var onOpenSetup: (() -> Void)?

    init(settings: AppSettings, engineName: String) {
        self.settings = settings; self.engineName = engineName
        self.stats = StatsStore(settings: settings)
        super.init()
        configureIcon()
        let menu = NSMenu()
        menu.delegate = self             // rebuild on open so checkmarks/status are fresh
        statusItem.menu = menu
    }

    /// Attach the coordinator once it has been built (permissions granted). Wires the
    /// state-changed callback so menu toggles and the panic hotkey persist their effect
    /// and keep the icon in sync, plus the stat event callbacks.
    func attach(_ coordinator: SuggestionCoordinator) {
        self.coordinator = coordinator
        coordinator.onStateChanged = { [weak self] in self?.stateDidChange() }
        coordinator.onAccept = { [weak self] words in self?.stats.recordAccept(words: words) }
        coordinator.onSuggestionLatency = { [weak self] ms in self?.stats.recordSuggestionLatency(ms: ms) }
        refreshIcon()   // restore ran before attach (no callback fired) — sync once
    }

    private func stateDidChange() { persistState(); refreshIcon(); onStateMirrored?() }

    private func persistState() {
        guard let coordinator else { return }
        settings.enabled = coordinator.isEnabled
        settings.pausedBundles = coordinator.pausedBundles
    }

    /// SF Symbol "eye" as a template image: adapts to light/dark menu bars automatically.
    /// pointSize is the one aesthetic knob — tweak here if live verification finds it off.
    private func configureIcon() {
        if let image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Seer")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) {
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageOnly
        } else {
            statusItem.button?.title = "S"   // unreachable for a built-in symbol; keeps the item clickable
        }
        refreshIcon()
    }

    /// Dimmed whenever Seer isn't suggesting: globally off, or pre-permission (no coordinator).
    private func refreshIcon() {
        statusItem.button?.appearsDisabled = !(coordinator?.isEnabled ?? false)
    }

    /// Seer itself is never a pause target. An .accessory app that activates — which
    /// SettingsWindow.show() must do for its window to come forward — becomes the frontmost
    /// application, so without this the menu offers "Pause for Seer" and pausing it lands a
    /// junk row in the Settings Apps tab that the user then has to hunt down and remove.
    /// PIDs, not bundle ids: exact, and no hardcoded identifier to drift. Same self-filter
    /// FocusObserver.retarget(to:) already applies before observing the frontmost app.
    /// Both frontmost readers below route through this — if only one did, the rendered item
    /// and the action it fires could disagree about which app they mean.
    private func frontmostNonSelf() -> NSRunningApplication? {
        let app = NSWorkspace.shared.frontmostApplication
        return app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app
    }
    private func currentBundleID() -> String? { frontmostNonSelf()?.bundleIdentifier }
    @objc private func toggleEnabled() {
        guard let coordinator else { return }
        coordinator.setEnabled(!coordinator.isEnabled)   // fires onStateChanged → stateDidChange
    }
    @objc private func togglePauseCurrent() {
        guard let coordinator, let b = currentBundleID() else { return }
        coordinator.setPaused(!coordinator.isPaused(bundleID: b), bundleID: b)   // fires onStateChanged → stateDidChange
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openSetup() { onOpenSetup?() }
}

extension MenuController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let coordinator {
            let onOff = NSMenuItem(title: "Seer Suggestions", action: #selector(toggleEnabled), keyEquivalent: "")
            onOff.target = self; onOff.state = coordinator.isEnabled ? .on : .off
            menu.addItem(onOff)
            // Item simply disappears while Seer's own Settings window is focused — consistent
            // with it already being conditional on there being a frontmost bundle at all.
            if let app = frontmostNonSelf(), let b = app.bundleIdentifier {
                let name = app.localizedName ?? b
                let pause = NSMenuItem(title: "Pause for \(name)", action: #selector(togglePauseCurrent), keyEquivalent: "")
                pause.target = self; pause.state = coordinator.isPaused(bundleID: b) ? .on : .off
                menu.addItem(pause)
            }
        } else {
            menu.addItem(disabledItem(setupStatusLine?() ?? "Waiting for permissions…"))
            if onOpenSetup != nil {
                let setupItem = NSMenuItem(title: "Open Setup…", action: #selector(openSetup), keyEquivalent: "")
                setupItem.target = self
                menu.addItem(setupItem)
            }
        }
        menu.addItem(.separator())
        let snap = stats.snapshot()
        menu.addItem(disabledItem(snap.wordsMenuLine))
        menu.addItem(disabledItem(snap.latencyMenuLine))
        let perms = PermissionsStatus.snapshot()
        menu.addItem(disabledItem("Engine: \(engineName)"))
        menu.addItem(disabledItem("Accessibility: \(perms.accessibility ? "✓" : "✗")   Input Monitoring: \(perms.inputMonitoring ? "✓" : "✗")"))
        menu.addItem(disabledItem("Panic: ⌃⌥⌘."))
        menu.addItem(.separator())
        if let target = updateCheckTarget, let action = updateCheckAction {
            let updateItem = NSMenuItem(title: "Check for Updates…", action: action, keyEquivalent: "")
            updateItem.target = target
            menu.addItem(updateItem)
        }
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: "Quit Seer", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    private func disabledItem(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""); i.isEnabled = false; return i
    }
}
