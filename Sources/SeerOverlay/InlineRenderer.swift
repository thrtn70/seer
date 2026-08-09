import AppKit
import SeerModel

@MainActor
public final class InlineRenderer: SuggestionRenderer {
    // Internal, not private (unlike PillRenderer's): SeerCoordinatorTests' dismiss-before-drop
    // guard reads `ghostPanel.panel.isVisible` to prove clear() ran before the renderer was
    // dropped. Deliberate asymmetry — don't "tidy" it back to private.
    let ghostPanel = GhostPanel()
    private let label = NSTextField(labelWithString: "")
    private var mode: RenderMode?

    public init(resolvedFont: ResolvedFont) {
        label.font = OverlayFont.nsFont(from: resolvedFont)
        label.textColor = .tertiaryLabelColor   // translucent gray ghost text
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        ghostPanel.setContentView(label)
    }

    public func update(text: String) {
        let display = GhostText.displayable(text)
        guard !display.isEmpty else { clear(); return }
        label.stringValue = display
        label.sizeToFit()
        reposition()
    }

    public func setPlacement(_ mode: RenderMode) {
        self.mode = mode
        if !label.stringValue.isEmpty { reposition() }
    }

    public func clear() {
        label.stringValue = ""
        ghostPanel.hide()
    }

    private func reposition() {
        guard let mode else { return }
        let size = label.frame.size
        ghostPanel.place(origin: OverlayPlacement.origin(for: mode, textSize: size), size: size)
    }
}
