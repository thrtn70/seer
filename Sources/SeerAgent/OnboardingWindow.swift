import AppKit
import SeerAppKit

/// First-run / recovery setup window: explains the two permission grants, deep-links the System
/// Settings panes, shows first-run model-download progress, live-polls status, and invokes
/// `onReady` exactly once — when both grants are in hand AND the model is installed.
/// (R11: also used on every launch when a grant is missing.)
@MainActor
final class OnboardingWindow: NSObject {
    private let window: NSWindow
    private let axRow = NSTextField(labelWithString: "")
    private let imRow = NSTextField(labelWithString: "")
    private let modelRow = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private var retryBtn: NSButton!
    private var timer: Timer?
    /// Three independent one-time concepts, deliberately not folded into `timer != nil`:
    /// `didPrompt` = the AX dialog has been raised; `didFinish` = onReady() has fired;
    /// `timer` = currently polling. They diverge the moment finish() runs (it nils the timer),
    /// so a single flag standing in for all three misreads "just finished" as "never started".
    private var didPrompt = false
    private var didFinish = false
    private let onReady: () -> Void
    /// Supplied by AgentDelegate. Defaults to `.ready` so the window behaves exactly as it did
    /// before Phase 14 if no downloader exists (e.g. Application Support unavailable).
    var modelStatus: () -> ModelDownloadController.State = { .ready }
    var onRetry: (() -> Void)?

    init(onReady: @escaping () -> Void) {
        self.onReady = onReady
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 330),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Seer — Setup"
        // AgentDelegate retains this window; the default (true) would over-release it if
        // the user closes with the red button instead of granting permissions.
        window.isReleasedWhenClosed = false
        super.init()
        buildContent()
        window.center()
    }
    /// Re-shows the window on every call; the AX prompt fires once and the poll timer is
    /// installed once. The old `guard timer == nil` at the top turned every call after the
    /// first into a silent no-op: a red-button close hides the window but deliberately leaves
    /// the timer polling, so the guard fired while nothing was on screen. This is the R11
    /// recovery surface, so a permanently un-showable window is not an acceptable end state.
    func show() {
        if !didPrompt { didPrompt = true; _ = PermissionsStatus.snapshot(promptAccessibility: true) }
        // Settle the readiness question BEFORE touching the window: with everything already in
        // hand there is nothing to show, and activate(ignoringOtherApps:) would rip focus out
        // of whatever the user is typing in to present a window that then never appears.
        let status = PermissionsStatus.snapshot()
        render(status)
        guard !isReady(status) else { finish(); return }
        // Re-entering setup (corrupt-model recovery re-shows this window after finish() already
        // ran). Without clearing didFinish, the later finish() short-circuits and the window is
        // never ordered out again — it would sit on screen reading "✓ installed" forever, with a
        // live poll timer. onReady firing twice is harmless: startCoordinator() is idempotent.
        didFinish = false
        NSApp.activate(ignoringOtherApps: true)   // accessory app: activate or it opens behind
        window.makeKeyAndOrderFront(nil)
        // Keep polling across red-button closes — it's the only thing that notices a grant
        // landing after the window was dismissed, and it drives finish() → onReady().
        if timer == nil {
            let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(t, forMode: .common); timer = t
        }
    }
    /// Pushed by AgentDelegate when the download state changes, so progress is live rather than
    /// waiting up to a second for the next poll tick. Also completes setup if the model was the
    /// last thing outstanding.
    func modelStateChanged() {
        let status = PermissionsStatus.snapshot()
        render(status)
        if isReady(status) { finish() }
    }
    /// Both gates: permissions AND a usable model.
    private func isReady(_ status: PermissionsStatus) -> Bool {
        status.allGranted && modelStatus().isReady
    }
    /// Idempotent: `onReady` fires exactly once. Previously safe only because
    /// startCoordinator() happens to guard on `coordinator == nil` — an implicit coupling
    /// across files that this class has no business relying on.
    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        timer?.invalidate(); timer = nil
        window.orderOut(nil)
        onReady()
    }
    /// Pure: paints the rows from a snapshot the caller already took. Split out so show()
    /// can render without re-snapshotting and without owning the finish decision.
    private func render(_ status: PermissionsStatus) {
        axRow.stringValue = "Accessibility: \(status.accessibility ? "✓ granted" : "✗ not granted")"
        imRow.stringValue = "Input Monitoring: \(status.inputMonitoring ? "✓ granted" : "✗ not granted")"
        renderModel(modelStatus())
    }
    private func renderModel(_ state: ModelDownloadController.State) {
        retryBtn.isHidden = true
        switch state {
        case .idle:
            modelRow.stringValue = "Language model: preparing…"
            showProgress(indeterminate: true, value: nil)
        case .downloading(let fraction, let detail):
            modelRow.stringValue = "Language model: \(detail)"
            showProgress(indeterminate: fraction == nil, value: fraction)
        case .verifying:
            modelRow.stringValue = "Language model: verifying…"
            showProgress(indeterminate: true, value: nil)
        case .ready:
            modelRow.stringValue = "Language model: ✓ installed"
            hideProgress()
        case .failed(let message):
            modelRow.stringValue = "Language model: ✗ \(message)"
            hideProgress()
            retryBtn.isHidden = false
        }
    }
    private func showProgress(indeterminate: Bool, value: Double?) {
        progress.isHidden = false
        progress.isIndeterminate = indeterminate
        if indeterminate { progress.startAnimation(nil) }
        else { progress.stopAnimation(nil); progress.doubleValue = value ?? 0 }
    }
    private func hideProgress() {
        progress.stopAnimation(nil)
        progress.isHidden = true
    }
    /// Timer tick: snapshot → render → finish once everything is ready.
    private func refresh() {
        let status = PermissionsStatus.snapshot()
        render(status)
        if isReady(status) { finish() }
    }
    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Seer needs two permissions to autocomplete in any app:")
        let why = NSTextField(wrappingLabelWithString:
            "• Accessibility — to read the focused text field and place ghost text.\n"
            + "• Input Monitoring — to detect Tab/Esc and insert accepted text.\n"
            + "Grant both below. This window closes automatically once they're on and the "
            + "language model has finished downloading.")
        let axBtn = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAX))
        let imBtn = NSButton(title: "Open Input Monitoring Settings", target: self, action: #selector(openIM))
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0; progress.maxValue = 1
        progress.isHidden = true
        retryBtn = NSButton(title: "Retry Download", target: self, action: #selector(retry))
        retryBtn.isHidden = true
        let modelNote = NSTextField(wrappingLabelWithString:
            "The language model (~1.1 GB) downloads once and is kept outside the app, so updates stay small.")
        modelNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        modelNote.textColor = .secondaryLabelColor
        [title, why, axRow, imRow, axBtn, imBtn, modelRow, progress, retryBtn, modelNote]
            .forEach { stack.addArrangedSubview($0) }
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            // The bar has no intrinsic width; without this it collapses to nothing.
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }
    @objc private func openAX() { NSWorkspace.shared.open(SystemSettingsLink.accessibility) }
    @objc private func openIM() { NSWorkspace.shared.open(SystemSettingsLink.inputMonitoring) }
    @objc private func retry() { retryBtn.isHidden = true; onRetry?() }
}
