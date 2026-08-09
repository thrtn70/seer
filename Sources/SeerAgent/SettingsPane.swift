import AppKit
import SeerAppKit
import SeerCoordinator

/// Shared scaffolding for the Settings tabs. Holds the two injected dependencies every pane
/// needs and defines the refresh() entry point SettingsWindow fans out to.
///
/// IMPORTANT: NSTabViewController loads tab views lazily, but SettingsWindow.refresh() calls
/// every pane's refresh() regardless of which tab is selected. So any property refresh()
/// touches must be initialized at its declaration — a property assigned in loadView() is nil
/// until that tab is first visited, and refresh() is reachable from the panic-chord path.
@MainActor
class SettingsPane: NSViewController {
    let settings: AppSettings
    /// Resolved through a closure because the coordinator may not exist yet (pre-permission);
    /// panes fall back to AppSettings-only writes, which startCoordinator() replays.
    let coordinator: () -> SuggestionCoordinator?

    init(settings: AppSettings, coordinator: @escaping () -> SuggestionCoordinator?) {
        self.settings = settings; self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("programmatic only") }

    /// Re-read persisted/coordinator state into this pane's controls. Must stay cheap and
    /// read-only: it runs on the keystroke path via the panic chord, and writing back through
    /// a coordinator setter here would feed back into itself.
    func refresh() {}

    func sectionLabel(_ title: String) -> NSTextField {
        let l = NSTextField(labelWithString: title)
        l.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        return l
    }
}
