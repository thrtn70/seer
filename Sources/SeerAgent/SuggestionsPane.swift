import AppKit
import SeerAppKit
import SeerCoordinator
import SeerModel

/// Suggestions tab: generation knobs (temperature, length) and the ghost-text font.
/// Values persist to AppSettings and live-apply through the coordinator when attached.
@MainActor
final class SuggestionsPane: SettingsPane {
    /// Index 0 of familyPopup — the "no explicit font" sentinel, mapping to fontName == nil.
    /// Verified not to collide with any installed family name.
    private static let systemFontItem = "System"
    /// All controls are initialized here rather than in loadView (target/action wired there, as
    /// GeneralPane/AppsPane do): NSTabViewController loads a tab's view lazily, so refresh() runs
    /// before loadView whenever Settings is open on another tab — and refresh() is reachable from
    /// the panic chord inside the CGEventTap callback. An implicitly-unwrapped control would crash
    /// on that path. familyPopup is item-less until loadView; refresh() is verified safe against
    /// that (selectItem(at:)/selectItem(withTitle:) on an empty popup are no-ops, not exceptions).
    private let tempSlider = NSSlider(value: AppSettings.defaultTemperature,
                                      minValue: AppSettings.temperatureRange.lowerBound,
                                      maxValue: AppSettings.temperatureRange.upperBound,
                                      target: nil, action: nil)
    private let tempValue = NSTextField(labelWithString: "")
    /// §7.4 as amended: ON ⇒ temperature derives from the learned brevity tone and the manual
    /// slider is disabled, displaying the derived value. The DISPLAYED value reads the current
    /// global tone; the EFFECTIVE value uses the per-focus-session pin and may lag until the
    /// next focus change — deliberate (§7.5 byte-stability), not a bug.
    private let autoCheck = NSButton(checkboxWithTitle: "Auto (match my style)",
                                     target: nil, action: nil)
    private let lengthSlider = NSSlider(value: Double(AppSettings.defaultMaxTokens),
                                        minValue: Double(AppSettings.maxTokensRange.lowerBound),
                                        maxValue: Double(AppSettings.maxTokensRange.upperBound),
                                        target: nil, action: nil)
    private let lengthValue = NSTextField(labelWithString: "")
    private let familyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizeField = NSTextField(string: "")
    private let sizeStepper = NSStepper()

    override func loadView() {
        // Continuous: tempValue/lengthValue are the only numeric readout (NSSlider has none
        // built in), so acting only on mouse-up would freeze the label for the whole drag.
        // applyGeneration updates those labels directly rather than calling refresh(), which
        // would write doubleValue back into the slider under the user's cursor.
        for slider in [tempSlider, lengthSlider] {
            slider.target = self
            slider.action = #selector(applyGeneration)
            slider.isContinuous = true
        }
        // No tick marks: 41 of them on a 220pt track renders as a dense ~5.4pt comb. The track
        // stays smooth and applyGeneration rounds to an integer instead.
        autoCheck.target = self
        autoCheck.action = #selector(applyAuto)

        familyPopup.addItem(withTitle: Self.systemFontItem)
        familyPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        })
        familyPopup.target = self; familyPopup.action = #selector(applyFont)

        sizeField.target = self; sizeField.action = #selector(applyFont)
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        sizeField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        sizeStepper.minValue = AppSettings.fontSizeRange.lowerBound
        sizeStepper.maxValue = AppSettings.fontSizeRange.upperBound
        sizeStepper.increment = 1
        // Defaults to true, and min/max bound the range without stopping the wrap: one up-click
        // at 96 would hand back 6 and collapse the ghost text. autorepeat (also on by default)
        // would then cycle 6→96→6 for as long as the arrow is held.
        sizeStepper.valueWraps = false
        sizeStepper.target = self; sizeStepper.action = #selector(sizeStepped)

        for slider in [tempSlider, lengthSlider] {
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        }
        let stack = NSStackView(views: [
            sectionLabel("Creativity (temperature)"), row(tempSlider, tempValue),
            row(autoCheck),
            sectionLabel("Suggestion length"), row(lengthSlider, lengthValue),
            sectionLabel("Ghost text font"), row(familyPopup, sizeField, sizeStepper),
        ])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 280))
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

    /// Read-only: re-reads persisted values into the controls. Must never write back through a
    /// coordinator setter — refresh() is itself reached from onStateChanged (via onStateMirrored)
    /// on the keystroke path, so a write here would re-enter and loop. Assigning doubleValue /
    /// stringValue / selectItem does not fire target/action, so the applyX → refresh → applyX
    /// loop cannot form (verified).
    override func refresh() {
        tempSlider.doubleValue = settings.temperature
        lengthSlider.doubleValue = Double(settings.maxTokens)
        updateGenerationLabels()
        autoCheck.state = settings.autoTemperature ? .on : .off
        tempSlider.isEnabled = !settings.autoTemperature
        // Stored name is a FACE name (e.g. "Menlo-Regular"); the popup lists FAMILIES ("Menlo").
        // Resolve back through NSFont to get the family, or the popup would never re-select.
        // indexOfItem(withTitle:) rather than itemTitles.contains: itemTitles allocates an array
        // of every family (180 here) on each call, and this runs per panic-chord press.
        if let name = settings.fontName,
           let family = NSFont(name: name, size: NSFont.systemFontSize)?.familyName,
           familyPopup.indexOfItem(withTitle: family) >= 0 {
            familyPopup.selectItem(withTitle: family)
        } else {
            familyPopup.selectItem(at: 0)
        }
        // Only when the field isn't being edited: refresh() arrives unbidden from the panic
        // chord and from menu toggles (the window resigns key without ending the field editor),
        // and assigning here would silently replace half-typed text. The commit path is
        // unaffected — AppKit relinquishes the field editor *before* sending the action, so
        // applyFont's own refresh() still writes back a clamped value (verified).
        if sizeField.currentEditor() == nil {
            sizeField.stringValue = String(format: "%g", settings.fontSize)
        }
        sizeStepper.doubleValue = settings.fontSize
    }

    private func updateGenerationLabels() {
        if settings.autoTemperature {
            // Current-global-tone hint; "learning" until the ≥20-sample threshold activates.
            if let derived = coordinator()?.autoTemperatureDisplayHint {
                tempValue.stringValue = String(format: "%.2f (auto)", derived)
            } else {
                tempValue.stringValue = "auto (learning)"
            }
        } else {
            tempValue.stringValue = String(format: "%.2f", settings.temperature)
        }
        lengthValue.stringValue = "\(settings.maxTokens) tokens"
    }

    /// Same write rule as applyGeneration: AppSettings first, then live-apply if attached.
    @objc private func applyAuto() {
        settings.autoTemperature = autoCheck.state == .on
        coordinator()?.setAutoTemperature(settings.autoTemperature)
        refresh()
    }

    private func row(_ views: NSView...) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal; r.spacing = 8
        return r
    }

    /// Write rule (differs from General/Apps): temperature/maxTokens are not coordinator-owned
    /// state, so AppSettings is the source of truth — write it first, then live-apply if a
    /// coordinator is attached. No else branch: startCoordinator() replays the persisted values
    /// when the coordinator later appears.
    @objc private func applyGeneration() {
        // Only write the manual temperature when Auto is off. While Auto is on the temp slider
        // is disabled and its value is the preserved manual setting; guarding the write here
        // (rather than relying on refresh() keeping the disabled slider synced) makes the
        // preservation explicit — this action is shared with the length slider, which stays
        // live under Auto and would otherwise round-trip a stale temperature.
        if !settings.autoTemperature {
            settings.temperature = (tempSlider.doubleValue * 100).rounded() / 100
        }
        // .rounded(), not integerValue: integerValue truncates, so a knob at 23.7 would read 23.
        settings.maxTokens = Int(lengthSlider.doubleValue.rounded())
        coordinator()?.setSamplingParams(SamplingParams(temperature: settings.temperature,
                                                        maxTokens: settings.maxTokens))
        // Labels only, never refresh(): this fires on every tick of a drag, and refresh() would
        // assign the rounded value back to the slider the user is dragging — visibly quantizing
        // the knob (~7pt per 0.01 of temperature on a 220pt track). The per-tick cost is a
        // property assignment plus a coalesced UserDefaults write.
        updateGenerationLabels()
    }
    @objc private func sizeStepped() {
        sizeField.stringValue = String(format: "%g", sizeStepper.doubleValue)
        applyFont()
    }
    @objc private func applyFont() {
        let raw = sizeField.doubleValue   // junk text parses to 0 → keep the current size
        let size = raw > 0
            ? min(max(raw, AppSettings.fontSizeRange.lowerBound), AppSettings.fontSizeRange.upperBound)
            : settings.fontSize
        settings.fontSize = size
        settings.fontName = selectedFontName()
        coordinator()?.setOverlayFont(name: settings.fontName, size: settings.fontSize)
        refresh()
    }
    /// Map the chosen family to a concrete face name — NSFont(name:size:) wants a face name, not
    /// a family, and OverlayFont.nsFont feeds the stored name straight to NSFont(name:size:),
    /// silently falling back to the system font if it doesn't resolve. Index 0 is the "System"
    /// sentinel; -1 (nothing selected — an item-less popup pre-loadView) is likewise not > 0.
    private func selectedFontName() -> String? {
        guard familyPopup.indexOfSelectedItem > 0, let family = familyPopup.titleOfSelectedItem
        else { return nil }
        let face = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13)
        return face?.fontName ?? family
    }
}
