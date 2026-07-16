import Testing
import AppKit
@testable import SeerOverlay

@Suite struct GhostPanelTests {
    @Test @MainActor func panelConstructsAndHides() {
        let p = GhostPanel()
        p.setContentView(NSView(frame: .zero))
        p.hide()                       // orderOut on a never-shown panel is safe
        #expect(p.panel.ignoresMouseEvents == true)
        #expect(p.panel.isOpaque == false)
    }
    @Test @MainActor func nsFontUsesResolvedSize() {
        let f = OverlayFont.nsFont(from: ResolvedFont(name: nil, size: 17))
        #expect(f.pointSize == 17)
    }
    @Test @MainActor func nsFontFallsBackOnUnknownName() {
        let f = OverlayFont.nsFont(from: ResolvedFont(name: "NoSuchFont_ZZZ", size: 20))
        #expect(f.pointSize == 20)     // falls back to system at the requested size
    }
}
