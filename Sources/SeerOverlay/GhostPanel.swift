import AppKit

/// Shared non-activating, click-through, borderless floating panel — the Phase-0
/// `OverlayPanel` NSPanel configuration, extracted so both renderers share one setup.
@MainActor
final class GhostPanel {
    let panel: NSPanel

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
    }

    func setContentView(_ view: NSView) { panel.contentView = view }

    func place(origin: CGPoint, size: CGSize) {
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}
