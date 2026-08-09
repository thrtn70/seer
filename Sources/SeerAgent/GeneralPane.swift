import AppKit
import SeerAppKit
import SeerCoordinator

/// General tab: global enable, permission status + deep links (recovery surface), engine.
@MainActor
final class GeneralPane: SettingsPane {
    private let engineName: String

    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enable Seer suggestions",
                                           target: nil, action: nil)
    private let axRow = NSTextField(labelWithString: "")
    private let imRow = NSTextField(labelWithString: "")

    init(settings: AppSettings, engineName: String,
         coordinator: @escaping () -> SuggestionCoordinator?) {
        self.engineName = engineName
        super.init(settings: settings, coordinator: coordinator)
    }
    /// Not inherited: declaring a new designated init above opts GeneralPane out of
    /// inheriting the base's initializers, so the required one must be restated.
    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func loadView() {
        enabledCheckbox.target = self
        enabledCheckbox.action = #selector(toggleEnabled)
        let axBtn = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAX))
        let imBtn = NSButton(title: "Open Input Monitoring Settings", target: self, action: #selector(openIM))
        let engineRow = NSTextField(labelWithString: "Engine: \(engineName)")
        engineRow.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [enabledCheckbox,
                                        sectionLabel("Permissions"), axRow, axBtn, imRow, imBtn,
                                        sectionLabel("Engine"), engineRow])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 270))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
        ])
        view = container
        // Pins the tab's size: without it the window resizes erratically between tabs.
        preferredContentSize = container.frame.size
        refresh()
    }

    override func refresh() {
        // Coordinator is runtime truth when attached; AppSettings pre-permission.
        enabledCheckbox.state = (coordinator()?.isEnabled ?? settings.enabled) ? .on : .off
        let s = PermissionsStatus.snapshot()
        axRow.stringValue = "Accessibility: \(s.accessibility ? "✓ granted" : "✗ not granted")"
        imRow.stringValue = "Input Monitoring: \(s.inputMonitoring ? "✓ granted" : "✗ not granted")"
    }

    @objc private func toggleEnabled() {
        let on = enabledCheckbox.state == .on
        // Write rule: mutate via the coordinator when attached — MenuController's
        // onStateChanged persists it. Writing settings.enabled directly here would be
        // overwritten by the next persistState(), and AppPolicy reads the coordinator's
        // in-memory value anyway. Pre-permission there is no coordinator, so write
        // AppSettings directly; startCoordinator() replays it once permissions land.
        if let c = coordinator() { c.setEnabled(on) } else { settings.enabled = on }
    }
    @objc private func openAX() { NSWorkspace.shared.open(SystemSettingsLink.accessibility) }
    @objc private func openIM() { NSWorkspace.shared.open(SystemSettingsLink.inputMonitoring) }
}
