import Testing
import CoreGraphics
import SeerModel
@testable import SeerOverlay

@MainActor
private final class SpyRenderer: SuggestionRenderer {
    var texts: [String] = []
    var placements: [RenderMode] = []
    var clears = 0
    func update(text: String) { texts.append(text) }
    func setPlacement(_ mode: RenderMode) { placements.append(mode) }
    func clear() { clears += 1 }
}

@Suite struct SuggestionRendererTests {
    @Test @MainActor func drivesThroughExistential() {
        let r: any SuggestionRenderer = SpyRenderer()
        r.setPlacement(.inline(CGRect(x: 0, y: 0, width: 2, height: 18)))
        r.update(text: " hi")
        r.clear()
        let spy = r as! SpyRenderer
        #expect(spy.placements.count == 1)
        #expect(spy.texts == [" hi"])
        #expect(spy.clears == 1)
    }
}
