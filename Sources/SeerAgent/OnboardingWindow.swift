import AppKit
import SeerAppKit

/// First-run / recovery permission window: explains the two grants, deep-links the System
/// Settings panes, live-polls status, and invokes `onGranted` once both are granted (R11:
/// also used on every launch when a grant is missing).
@MainActor
final class OnboardingWindow: NSObject {
    private let window: NSWindow
    private let axRow = NSTextField(labelWithString: "")
    private let imRow = NSTextField(labelWithString: "")
    private var timer: Timer?
    private let onGranted: () -> Void
    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Seer — Permissions"
        super.init()
        buildContent()
        window.center()
    }
    func show() {
        guard timer == nil else { return }   // idempotent: already showing + polling
        // Prompt the AX dialog once on first show; then poll.
        _ = PermissionsStatus.snapshot(promptAccessibility: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        refresh()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
    private func finish() { timer?.invalidate(); timer = nil; window.orderOut(nil); onGranted() }
    private func refresh() {
        let s = PermissionsStatus.snapshot()
        axRow.stringValue = "Accessibility: \(s.accessibility ? "✓ granted" : "✗ not granted")"
        imRow.stringValue = "Input Monitoring: \(s.inputMonitoring ? "✓ granted" : "✗ not granted")"
        if s.allGranted { finish() }
    }
    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Seer needs two permissions to autocomplete in any app:")
        let why = NSTextField(wrappingLabelWithString:
            "• Accessibility — to read the focused text field and place ghost text.\n"
            + "• Input Monitoring — to detect Tab/Esc and insert accepted text.\n"
            + "Grant both below; this window closes automatically when they're on.")
        let axBtn = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAX))
        let imBtn = NSButton(title: "Open Input Monitoring Settings", target: self, action: #selector(openIM))
        [title, why, axRow, imRow, axBtn, imBtn].forEach { stack.addArrangedSubview($0) }
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
        ])
    }
    @objc private func openAX() { NSWorkspace.shared.open(SystemSettingsLink.accessibility) }
    @objc private func openIM() { NSWorkspace.shared.open(SystemSettingsLink.inputMonitoring) }
}
