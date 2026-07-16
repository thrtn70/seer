import AppKit

@MainActor
final class OverlayPanel {
    private let panel: NSPanel
    private let label: NSTextField

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        label = NSTextField(labelWithString: "")
        label.textColor = NSColor.tertiaryLabelColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        panel.contentView = label
    }

    func show(text: String, at caretRect: CGRect, font: NSFont) {
        guard !text.isEmpty else { hide(); return }
        label.font = font
        label.stringValue = text
        label.sizeToFit()
        let size = label.frame.size
        // AX (e.g. TextEdit) reports the caret rect at the line-fragment top, ~one line above
        // the rendered glyph baseline, so the ghost text would float above the user's text.
        // Drop it by the caret height to sit on the line. (Phase 1: per-app baseline calibration.)
        let origin = CGPoint(x: caretRect.maxX, y: caretRect.minY - caretRect.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}
