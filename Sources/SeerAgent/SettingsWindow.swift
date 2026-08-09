import AppKit
import SeerAppKit
import SeerCoordinator
import SeerPersonalization

/// Settings window: native toolbar-tabbed panes, programmatic AppKit following
/// OnboardingWindow's pattern; retained by AgentDelegate. The coordinator is resolved
/// through a closure because it may not exist yet (pre-permission) — panes fall back to
/// AppSettings-only writes, which startCoordinator() replays once permissions land.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    /// The tabs, in toolbar order, held as the shared base type so refresh() can fan out
    /// structurally. Deliberately not three named properties: their only use was that fan-out,
    /// and hand-enumerating it meant a newly added pane could silently never refresh.
    private let panes: [SettingsPane]

    init(settings: AppSettings, engineName: String,
         coordinator: @escaping () -> SuggestionCoordinator?,
         profileStore: @escaping () -> StyleProfileStore?,
         profileCache: @escaping () -> ProfileCache?) {
        // One list drives both the toolbar and the refresh fan-out — they cannot drift apart.
        let tabDefs: [(SettingsPane, String, String)] = [
            (GeneralPane(settings: settings, engineName: engineName, coordinator: coordinator),
             "General", "gearshape"),
            (AppsPane(settings: settings, coordinator: coordinator),
             "Apps", "square.grid.2x2"),
            (SuggestionsPane(settings: settings, coordinator: coordinator),
             "Suggestions", "text.cursor"),
            (StylePane(settings: settings, coordinator: coordinator,
                       profileStore: profileStore, profileCache: profileCache),
             "Style", "paintpalette"),
        ]
        panes = tabDefs.map { $0.0 }
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for (pane, label, symbol) in tabDefs {
            let item = NSTabViewItem(viewController: pane)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            tabs.addTabViewItem(item)
        }
        window = NSWindow(contentViewController: tabs)
        // The initializer picks its own mask (titled/closable/miniaturizable/resizable);
        // narrow it to match Xcode's Settings window — dropping .resizable removes both resize
        // and zoom, and dropping .miniaturizable removes the minimise button (a Settings window
        // has nowhere to un-minimise from in an accessory app: no Dock tile). `.titled` is
        // retained deliberately: NSTabViewController only installs its toolbar on a titled window.
        window.styleMask = [.titled, .closable]
        // Stored on the window and applied to the toolbar NSTabViewController installs when
        // the tab VC's view moves to the window — not a no-op despite `toolbar` being nil here.
        window.toolbarStyle = .preference
        // Retained by AgentDelegate; the default (true) would over-release on red-button close.
        window.isReleasedWhenClosed = false
        window.title = "Seer Settings"
        super.init()
        window.delegate = self
        window.center()   // first-run default only
        // Restores the saved frame over center() when one exists, and autosaves every move
        // thereafter, so position survives relaunches.
        window.setFrameAutosaveName("SeerSettings")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)   // accessory app: activate or it opens behind
        window.makeKeyAndOrderFront(nil)          // → windowDidBecomeKey → refresh(), when not already key
        refresh()                                 // covers the already-key re-show
    }

    /// Re-read coordinator/AppSettings state into all panes (menu toggles, panic, grants).
    /// Guarded: this is reachable from the panic chord *inside* the CGEventTap callback
    /// (tap.onKeyDown → panic → setEnabled → onStateChanged → stateDidChange → onStateMirrored),
    /// and AgentDelegate retains this window forever once created — so a closed Settings window
    /// must not tax the keystroke path. Today that's two TCC preflights per panic press; Task 8's
    /// AppsPane adds Launch Services lookups per row. Reopening always refreshes via show(),
    /// so nothing goes stale. isVisible (not isKeyWindow): an on-screen but inactive window
    /// still mirrors live, which is what the user sees.
    func refresh() {
        guard window.isVisible else { return }
        panes.forEach { $0.refresh() }
    }

    func windowDidBecomeKey(_ notification: Notification) { refresh() }
}
