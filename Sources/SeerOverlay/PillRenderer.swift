import AppKit
import SeerModel

@MainActor
public final class PillRenderer: SuggestionRenderer {
    private let ghostPanel = GhostPanel()
    private let container = NSView(frame: .zero)
    private let label = NSTextField(labelWithString: "")
    private var mode: RenderMode?

    private let hPad: CGFloat = 8
    private let vPad: CGFloat = 4

    public init(resolvedFont: ResolvedFont) {
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        container.layer?.cornerRadius = 6
        label.font = OverlayFont.nsFont(from: resolvedFont)
        label.textColor = .secondaryLabelColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        container.addSubview(label)
        ghostPanel.setContentView(container)
    }

    public func update(text: String) {
        let display = GhostText.displayable(text)
        guard !display.isEmpty else { clear(); return }
        label.stringValue = display
        label.sizeToFit()
        let ls = label.frame.size
        label.frame = CGRect(x: hPad, y: vPad, width: ls.width, height: ls.height)
        container.frame = CGRect(x: 0, y: 0, width: ls.width + hPad * 2, height: ls.height + vPad * 2)
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
        let size = container.frame.size
        ghostPanel.place(origin: OverlayPlacement.origin(for: mode, textSize: size), size: size)
    }
}
