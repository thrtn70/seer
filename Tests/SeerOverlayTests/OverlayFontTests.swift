import Testing
@testable import SeerOverlay

@Suite struct OverlayFontTests {
    @Test func nilNameResolvesToSystem() {
        let r = OverlayFont.resolve(FontDescriptorInput(name: nil, size: 14))
        #expect(r.name == nil)
        #expect(r.size == 14)
    }
    @Test func blankNameResolvesToSystem() {
        let r = OverlayFont.resolve(FontDescriptorInput(name: "   ", size: 14))
        #expect(r.name == nil)
    }
    @Test func validNamePassesThrough() {
        let r = OverlayFont.resolve(FontDescriptorInput(name: "Menlo", size: 12))
        #expect(r.name == "Menlo")
        #expect(r.size == 12)
    }
    @Test func nilSizeFallsToDefault() {
        let r = OverlayFont.resolve(FontDescriptorInput(name: "Menlo", size: nil))
        #expect(r.size == OverlayFont.defaultSize)
    }
    @Test func outOfRangeSizeFallsToDefault() {
        #expect(OverlayFont.resolve(FontDescriptorInput(name: nil, size: 0)).size == OverlayFont.defaultSize)
        #expect(OverlayFont.resolve(FontDescriptorInput(name: nil, size: -5)).size == OverlayFont.defaultSize)
        #expect(OverlayFont.resolve(FontDescriptorInput(name: nil, size: 9999)).size == OverlayFont.defaultSize)
    }
}
