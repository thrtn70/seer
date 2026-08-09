import AppKit
import UniformTypeIdentifiers
import SeerAppKit
import SeerCoordinator

/// Apps tab: the paused/excluded apps list — the same set the menu's "Pause for <App>"
/// toggles. Uninstalled apps show their raw bundle id and stay removable.
@MainActor
final class AppsPane: SettingsPane, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    /// Initialized here rather than in loadView (target/action wired there, as GeneralPane does):
    /// NSTabViewController loads a tab's view lazily, so refresh() runs before loadView whenever
    /// Settings is open on another tab — an implicitly-unwrapped button would crash on that path.
    private let removeBtn = NSButton(title: "Remove", target: nil, action: nil)
    private var rows: [ExcludedAppRow] = []
    /// Bundle id → app URL on disk, rebuilt wholesale by `refresh()`; a missing key means the
    /// id didn't resolve (not installed). Exists purely to keep Launch Services off the row
    /// path: `urlForApplication` is an LS round-trip, and `tableView(_:viewFor:row:)` runs for
    /// every visible row on each reload *and* again on scroll (view recycling), so resolving
    /// there would be unbounded LS traffic — on a path reachable from the panic chord inside
    /// the CGEventTap callback (onKeyDown → panic → setEnabled → onStateChanged →
    /// stateDidChange → onStateMirrored → SettingsWindow.refresh) whenever Settings is open.
    private var urlByBundleID: [String: URL] = [:]

    override func loadView() {
        let column = NSTableColumn(identifier: .init("app"))
        // Single column: let it track the table's width so long names truncate at the real
        // edge rather than at a fixed default width.
        column.resizingMask = .autoresizingMask
        column.width = 380
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let addBtn = NSButton(title: "Add App…", target: self, action: #selector(addApp))
        removeBtn.target = self
        removeBtn.action = #selector(removeSelected)
        let buttons = NSStackView(views: [addBtn, removeBtn])
        buttons.orientation = .horizontal; buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString:
            "Seer never suggests in these apps. The menu bar’s “Pause for <App>” toggles the same list.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 320))
        [scroll, buttons, hint].forEach { container.addSubview($0) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scroll.heightAnchor.constraint(equalToConstant: 200),
            buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            buttons.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            hint.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
        view = container
        // Pins the tab's size: without it the window resizes erratically between tabs.
        preferredContentSize = container.frame.size
        refresh()
    }

    /// Read-only: re-reads the paused set and reloads. Must never write back through a
    /// coordinator setter — refresh() is itself reached from onStateChanged (via
    /// onStateMirrored), so a write here would re-enter and loop.
    override func refresh() {
        // Coordinator is runtime truth when attached; AppSettings pre-permission.
        let ids = coordinator()?.pausedBundles ?? settings.pausedBundles
        // rows(bundleIDs:resolveName:) invokes resolveName exactly once per id, so piggybacking
        // the URL cache on it costs the pane exactly one LS lookup per paused app per refresh.
        var urls: [String: URL] = [:]
        rows = ExcludedAppsListModel.rows(bundleIDs: ids, resolveName: { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
            // A blank name is "not installed" to the model, and iconFor only reads the cache for
            // installed rows — so returning nil (equivalent to blank, per rows(bundleIDs:)'s
            // contract) keeps out an entry nothing could ever read.
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            urls[id] = url
            return name
        })
        urlByBundleID = urls
        table.reloadData()
        // Also covers the initial (empty) selection at loadView, which fires no delegate callback.
        updateRemoveEnabled()
    }

    /// HIG: Remove is meaningless with nothing selected. Driven from both refresh() and the
    /// selection-changed delegate so the button is right regardless of which moved the selection.
    private func updateRemoveEnabled() { removeBtn.isEnabled = !table.selectedRowIndexes.isEmpty }

    // MARK: - Table
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = rows[row]
        let cell = NSTableCellView()
        let icon = NSImageView(image: iconFor(r) ?? NSImage())
        // Sizing lives here, not on the NSImage: icon(forFile:) is served from a process-wide
        // cache and isn't documented to hand back a copy, so setting `size` on it would mutate a
        // framework-owned object process-wide. The 16×16 constraints below do the sizing instead.
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextField(labelWithString: r.displayName)
        text.lineBreakMode = .byTruncatingMiddle
        text.textColor = r.installed ? .labelColor : .secondaryLabelColor
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon); cell.addSubview(text)
        // NSTableCellView's documented outlets for its image/text subviews. Weak, so they must
        // be assigned after addSubview. Not load-bearing for selection contrast — backgroundStyle
        // forwards to every NSControl subview regardless (NSTableCellView.h) — just the hookup a
        // reader expects to find on an NSTableCellView.
        cell.imageView = icon
        cell.textField = text
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
    /// Reads the cache refresh() built — deliberately does not resolve; see `urlByBundleID`.
    private func iconFor(_ r: ExcludedAppRow) -> NSImage? {
        if r.installed, let url = urlByBundleID[r.bundleID] {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: "Not installed")
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateRemoveEnabled() }

    // MARK: - Actions
    @objc private func addApp() {
        guard let sheetParent = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")   // default, not a restriction
        panel.beginSheetModal(for: sheetParent) { [weak self] response in
            guard let self, response == .OK else { return }
            for url in panel.urls {
                guard let id = Bundle(url: url)?.bundleIdentifier else { NSSound.beep(); continue }
                // Nothing stops the panel being navigated to Seer.app itself, and pausing Seer in
                // Seer is meaningless — it would just seed the junk row the menu's own self-filter
                // (MenuController.frontmostNonSelf) exists to prevent. Beep rather than skip
                // silently, matching the malformed-bundle case above: the row won't appear either
                // way, and silence would read as a bug. Bundle id, not PID — there's no running-app
                // object for a URL the user merely picked. A nil main bundle id can't match, which
                // fails open (add proceeds) — the same behavior as before this guard.
                guard id != Bundle.main.bundleIdentifier else { NSSound.beep(); continue }
                self.setPaused(id, paused: true)
            }
            // Inserted rows shift indexes under any existing selection, and reloadData reconciles
            // selection against the new row *count*, not row identity — so a surviving index now
            // points at whichever app sorted into that slot. Drop it rather than leave the user
            // with a highlighted row they never picked.
            self.table.deselectAll(nil)
            self.refresh()
        }
    }
    @objc private func removeSelected() {
        // Resolve indices to ids BEFORE mutating: each setPaused re-enters refresh() via the
        // coordinator's onStateChanged, which re-sorts and re-indexes `rows` under us.
        let selected = table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].bundleID : nil }
        guard !selected.isEmpty else { return }
        for id in selected { setPaused(id, paused: false) }
        // Snapshotting ids above protects the loop, not the selection: reloadData only drops
        // out-of-range indexes, so removing [A, C] from [A, B, C] leaves index 0 selected —
        // now pointing at B, which a second Remove click would delete.
        table.deselectAll(nil)
        // Load-bearing, not belt-and-braces: pre-permission setPaused writes AppSettings and
        // fires no callback, so this is the only refresh on that path. It's redundant only when
        // the coordinator is attached and onStateChanged already re-entered refresh().
        refresh()
    }
    /// Write rule: mutate via the coordinator when attached (MenuController persists);
    /// pre-permission write AppSettings directly (replayed by startCoordinator()).
    private func setPaused(_ bundleID: String, paused: Bool) {
        if let c = coordinator() {
            c.setPaused(paused, bundleID: bundleID)
        } else if paused {
            settings.pausedBundles.insert(bundleID)
        } else {
            settings.pausedBundles.remove(bundleID)
        }
    }
}
