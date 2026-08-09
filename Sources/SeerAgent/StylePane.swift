import AppKit
import UniformTypeIdentifiers
import SeerAppKit
import SeerCoordinator
import SeerModel
import SeerPersonalization

/// Style tab (§7.7): view the learned tone axes + per-app phrases, pin axes manually
/// (per-axis, global scope), export with §7.8 redaction, and reset per-app or globally.
/// Reads ProfileCache synchronously in refresh(); every mutation goes through
/// StyleProfileStore from button/gesture actions only.
@MainActor
final class StylePane: SettingsPane, NSTableViewDataSource, NSTableViewDelegate {
    private enum Axis: Int, CaseIterable {
        case formality, warmth, brevity
        var title: String {
            switch self {
            case .formality: return "Formality"
            case .warmth: return "Warmth"
            case .brevity: return "Brevity"
            }
        }
        func derived(from tone: ToneScores) -> Double {
            switch self {
            case .formality: return tone.formality
            case .warmth: return tone.warmth
            case .brevity: return tone.brevity
            }
        }
        func pinned(in o: ToneOverrides) -> Double? {
            switch self {
            case .formality: return o.formality
            case .warmth: return o.warmth
            case .brevity: return o.brevity
            }
        }
        func replacing(in o: ToneOverrides, with v: Double?) -> ToneOverrides {
            ToneOverrides(formality: self == .formality ? v : o.formality,
                          warmth: self == .warmth ? v : o.warmth,
                          brevity: self == .brevity ? v : o.brevity)
        }
    }

    /// Resolved through closures like `coordinator` — the store/cache don't exist
    /// pre-permission. Pre-permission behavior: sliders are disabled (no active tone yet);
    /// a leftover pin's Revert still writes AppSettings (replayed via the store's init
    /// param); export/reset disable.
    private let profileStore: () -> StyleProfileStore?
    private let profileCache: () -> ProfileCache?

    // All controls initialized at declaration (lazy-tab/panic-path rule — see SettingsPane).
    private let sliders = Axis.allCases.map { _ in
        NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    }
    private let valueLabels = Axis.allCases.map { _ in NSTextField(labelWithString: "") }
    private let revertButtons = Axis.allCases.map { _ in
        NSButton(title: "Revert", target: nil, action: nil)
    }
    private let toneStatus = NSTextField(labelWithString: "")
    private let appTable = NSTableView()
    private let phrasesLabel = NSTextField(wrappingLabelWithString: "")
    private let resetAppBtn = NSButton(title: "Reset App…", target: nil, action: nil)
    private let exportBtn = NSButton(title: "Export…", target: nil, action: nil)
    private let rawTextCheck = NSButton(checkboxWithTitle: "Include raw accepted text",
                                        target: nil, action: nil)
    private let resetAllBtn = NSButton(title: "Reset All…", target: nil, action: nil)

    private var appRows: [(bundleID: String, displayName: String, sampleCount: Int)] = []
    private var phrasesByBundleID: [String: [String]] = [:]
    /// Launch Services results cached across refreshes (AppsPane rationale: LS stays off the
    /// panic-chord path). Bounded by the profile's own learned-app set.
    private var nameByBundleID: [String: String] = [:]
    private var overridesCommit: Task<Void, Never>?

    init(settings: AppSettings, coordinator: @escaping () -> SuggestionCoordinator?,
         profileStore: @escaping () -> StyleProfileStore?,
         profileCache: @escaping () -> ProfileCache?) {
        self.profileStore = profileStore
        self.profileCache = profileCache
        super.init(settings: settings, coordinator: coordinator)
    }
    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func loadView() {
        for (i, slider) in sliders.enumerated() {
            slider.target = self
            slider.action = #selector(sliderMoved(_:))
            slider.isContinuous = true
            slider.tag = i
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.widthAnchor.constraint(equalToConstant: 170).isActive = true
        }
        for (i, btn) in revertButtons.enumerated() {
            btn.target = self
            btn.action = #selector(revertAxis(_:))
            btn.tag = i
            btn.controlSize = .small
        }
        toneStatus.textColor = .secondaryLabelColor
        toneStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let column = NSTableColumn(identifier: .init("style-app"))
        column.resizingMask = .autoresizingMask
        column.width = 380
        appTable.addTableColumn(column)
        appTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        appTable.headerView = nil
        appTable.rowHeight = 20
        appTable.dataSource = self
        appTable.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = appTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true

        phrasesLabel.textColor = .secondaryLabelColor
        phrasesLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        phrasesLabel.translatesAutoresizingMaskIntoConstraints = false

        // Fixed width so the Revert button doesn't shift as "5/10 · learned" becomes
        // "10/10 · manual" mid-drag.
        for label in valueLabels {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 96).isActive = true
        }

        resetAppBtn.target = self; resetAppBtn.action = #selector(resetSelectedApp)
        exportBtn.target = self; exportBtn.action = #selector(exportProfile)
        resetAllBtn.target = self; resetAllBtn.action = #selector(resetAllProfiles)

        let rawHint = NSTextField(wrappingLabelWithString:
            "Exports contain derived stats, tone, and phrases. With the checkbox on, the file "
            + "also includes your raw accepted text and up to 200 characters of context per "
            + "acceptance — treat that file as sensitive.")
        rawHint.textColor = .secondaryLabelColor
        rawHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        rawHint.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = [sectionLabel("Tone"), toneStatus]
        for axis in Axis.allCases {
            views.append(row(axisLabel(axis.title), sliders[axis.rawValue],
                             valueLabels[axis.rawValue], revertButtons[axis.rawValue]))
        }
        views += [sectionLabel("Learned apps & phrases"), scroll, phrasesLabel, row(resetAppBtn),
                  sectionLabel("Your data"), row(exportBtn, rawTextCheck), rawHint, row(resetAllBtn)]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 560))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            scroll.widthAnchor.constraint(equalToConstant: 400),
            phrasesLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
            rawHint.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
        ])
        view = container
        // Pins the tab's size: without it the window resizes erratically between tabs.
        preferredContentSize = container.frame.size
        refresh()
    }

    /// Read-only: snapshot + settings into controls; never a store/coordinator call (this is
    /// reachable from the panic chord via SettingsWindow.refresh()). The raw-text checkbox is
    /// deliberately NOT touched here — it re-arms to off only after a completed export, so an
    /// unbidden refresh can't uncheck it under the user (§7.8 amendment).
    override func refresh() {
        let snapshot = profileCache()?.snapshot
        let overrides = settings.toneOverrides
        let active = snapshot?.global != nil
        for axis in Axis.allCases {
            let pinned = axis.pinned(in: overrides)
            let shown = pinned ?? (snapshot?.global).map(axis.derived(from:)) ?? 0.5
            sliders[axis.rawValue].isEnabled = active
            sliders[axis.rawValue].doubleValue = shown
            if active || pinned != nil {
                valueLabels[axis.rawValue].stringValue =
                    "\(Int((shown * 10).rounded()))/10 · \(pinned != nil ? "manual" : "learned")"
            } else {
                valueLabels[axis.rawValue].stringValue = "—"
            }
            // Enabled while dormant too (post-reset, pre-threshold): un-pinning must never
            // require 20 samples of relearning first.
            revertButtons[axis.rawValue].isEnabled = pinned != nil
        }
        toneStatus.isHidden = active
        if !active {
            let n = min(snapshot?.totalSamples ?? 0, ProfileThresholds.globalActivation)
            toneStatus.stringValue = "Learning your style — \(n) of "
                + "\(ProfileThresholds.globalActivation) samples. Sliders unlock once the tone activates."
        }
        rebuildAppRows(from: snapshot)
        appTable.reloadData()
        updateSelectionDependentUI()
        let storeAvailable = profileStore() != nil
        exportBtn.isEnabled = storeAvailable
        resetAllBtn.isEnabled = storeAvailable
        rawTextCheck.isEnabled = storeAvailable
    }

    private func rebuildAppRows(from snapshot: ProfileSnapshot?) {
        phrasesByBundleID = snapshot?.apps.mapValues { $0.phrases } ?? [:]
        appRows = (snapshot?.apps ?? [:]).sorted { $0.key < $1.key }.map { bundle, app in
            (bundleID: bundle, displayName: resolveName(bundle), sampleCount: app.sampleCount)
        }
    }
    private func resolveName(_ bundleID: String) -> String {
        if let cached = nameByBundleID[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return bundleID }        // uninstalled: raw id; not cached — it may install later
        let name = FileManager.default.displayName(atPath: url.path)
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return bundleID }
        nameByBundleID[bundleID] = name
        return name
    }

    // MARK: - Table
    func numberOfRows(in tableView: NSTableView) -> Int { appRows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = appRows[row]
        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: "\(r.displayName) — \(r.sampleCount) samples")
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateSelectionDependentUI() }
    private func updateSelectionDependentUI() {
        let row = appTable.selectedRow
        let hasSelection = appRows.indices.contains(row)
        resetAppBtn.isEnabled = hasSelection && profileStore() != nil
        if hasSelection {
            let phrases = phrasesByBundleID[appRows[row].bundleID] ?? []
            phrasesLabel.stringValue = phrases.isEmpty
                ? "No repeated phrases learned in this app yet."
                : "Often writes: " + phrases.map { "“\($0)”" }.joined(separator: ", ")
        } else {
            phrasesLabel.stringValue = "Select an app to see its learned phrases."
        }
    }

    // MARK: - Tone actions
    @objc private func sliderMoved(_ sender: NSSlider) {
        guard let axis = Axis(rawValue: sender.tag) else { return }
        let value = (sender.doubleValue * 100).rounded() / 100
        settings.toneOverrides = axis.replacing(in: settings.toneOverrides, with: value)
        // Labels only per tick — refresh() would write doubleValue back into the slider
        // under the cursor (SuggestionsPane precedent).
        valueLabels[axis.rawValue].stringValue = "\(Int((value * 10).rounded()))/10 · manual"
        revertButtons[axis.rawValue].isEnabled = true
        commitOverrides()
    }
    @objc private func revertAxis(_ sender: NSButton) {
        guard let axis = Axis(rawValue: sender.tag) else { return }
        settings.toneOverrides = axis.replacing(in: settings.toneOverrides, with: nil)
        commitOverrides()
        refresh()      // button click, not a drag — safe (AppsPane precedent)
    }
    /// Coalesced store commit: every tick (drag, scroll wheel, keyboard, AX) just re-arms a
    /// short trailing debounce; one commit fires after the LAST change, reading the freshest
    /// settings value at fire time — not capture time — so a queued commit can never land a
    /// stale value. Cancellation is real here (Task.sleep throws on cancel, so a superseded
    /// commit dies in the sleep). This replaces gesture-end event-type detection, which
    /// missed scroll-wheel and accessibility-driven slider changes entirely.
    private func commitOverrides() {
        guard profileStore() != nil else { return }   // pre-permission: settings-only, replayed at init
        overridesCommit?.cancel()
        overridesCommit = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, let store = self.profileStore() else { return }
            await store.setOverrides(self.settings.toneOverrides)
        }
    }

    // MARK: - Data actions
    @objc private func exportProfile() {
        guard let sheetParent = view.window, let store = profileStore() else { return }
        let includeRaw = rawTextCheck.state == .on
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Seer Style Profile.json"
        panel.beginSheetModal(for: sheetParent) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                do {
                    let data = try await store.exportPayload(includeRawText: includeRaw)
                    // Off-main write: the save panel accepts any volume, and a stalled
                    // network/USB write on the main actor would starve the CGEventTap
                    // (its callback shares this runloop).
                    try await Task.detached { try data.write(to: url) }.value
                    self?.rawTextCheck.state = .off      // §7.8: the opt-in never sticks
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Export failed"
                    alert.informativeText = error.localizedDescription
                    if let window = self?.view.window {
                        alert.beginSheetModal(for: window, completionHandler: nil)
                    } else {
                        alert.runModal()
                    }
                }
            }
        }
    }
    @objc private func resetSelectedApp() {
        let row = appTable.selectedRow
        guard appRows.indices.contains(row), let store = profileStore(),
              let sheetParent = view.window else { return }
        let target = appRows[row]
        let alert = NSAlert()
        alert.messageText = "Reset learned style for “\(target.displayName)”?"
        alert.informativeText = "Seer forgets what it learned from your accepted suggestions "
            + "in this app. Manual tone pins are kept."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        markDestructive(alert)
        alert.beginSheetModal(for: sheetParent) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performReset { await store.resetApp(target.bundleID) }
        }
    }
    @objc private func resetAllProfiles() {
        guard let store = profileStore(), let sheetParent = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Reset everything Seer has learned?"
        alert.informativeText = "Seer forgets everything it has learned in every app and "
            + "overwrites the encrypted profile on disk with an empty one. Manual tone pins "
            + "are kept."
        alert.addButton(withTitle: "Reset All")
        alert.addButton(withTitle: "Cancel")
        markDestructive(alert)
        alert.beginSheetModal(for: sheetParent) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performReset { await store.resetAll() }
        }
    }
    /// HIG: the destructive choice must not be the Return-key default. First button (the
    /// reset) renders destructive-red and loses its key equivalent; Cancel takes Return.
    /// Esc keeps mapping to the button titled "Cancel" automatically.
    private func markDestructive(_ alert: NSAlert) {
        alert.buttons[0].hasDestructiveAction = true
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
    }
    /// Reset choreography (§7.7 immediacy): discard unflushed learning + end the focus
    /// session BEFORE the store mutation (a dismiss-flush would resurrect a sample), then
    /// invalidate AGAIN after the publish lands (a keystroke in between can re-pin from the
    /// stale cache). The coordinator resolver is captured directly — the second, window-
    /// closing invalidation must not silently vanish if the pane ever deallocates mid-await.
    private func performReset(_ mutation: @escaping @Sendable () async -> Void) {
        let coordinator = coordinator
        coordinator()?.prepareForProfileReset()
        appTable.deselectAll(nil)          // rows are about to be rebuilt under the selection
        Task { @MainActor [weak self] in
            await mutation()
            coordinator()?.prepareForProfileReset()
            self?.refresh()
        }
    }

    // MARK: - Layout helpers
    private func row(_ views: NSView...) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.spacing = 8
        return r
    }
    private func axisLabel(_ title: String) -> NSTextField {
        let l = NSTextField(labelWithString: title)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 64).isActive = true
        return l
    }
}
