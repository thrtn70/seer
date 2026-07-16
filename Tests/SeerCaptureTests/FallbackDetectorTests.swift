import Testing
import CoreGraphics
import SeerModel
@testable import SeerCapture

@Suite struct FallbackDetectorTests {
    let rect = CGRect(x: 100, y: 200, width: 2, height: 18)

    @Test func inlineWhenCaretValidSelectedAndGoodBundle() {
        let mode = FallbackDetector.renderMode(
            caretRect: rect, hasSelectedRange: true, bundleID: "com.apple.TextEdit",
            knownBadBundles: [], mousePoint: nil, windowTopAnchor: nil)
        #expect(mode == .inline(rect))
    }
    @Test func pillWhenNoCaretRect() {
        let mode = FallbackDetector.renderMode(
            caretRect: nil, hasSelectedRange: true, bundleID: "com.apple.TextEdit",
            knownBadBundles: [], mousePoint: CGPoint(x: 5, y: 6), windowTopAnchor: nil)
        #expect(mode == .pill(CGPoint(x: 5, y: 6)))
    }
    @Test func pillWhenBundleKnownBad() {
        let mode = FallbackDetector.renderMode(
            caretRect: rect, hasSelectedRange: true, bundleID: "com.tinyspeck.slackmacgap",
            knownBadBundles: ["com.tinyspeck.slackmacgap"], mousePoint: nil, windowTopAnchor: nil)
        #expect(mode == .pill(CGPoint(x: rect.minX, y: rect.minY)))
    }
    @Test func pillWhenNoSelectedRange() {
        let mode = FallbackDetector.renderMode(
            caretRect: rect, hasSelectedRange: false, bundleID: "com.apple.TextEdit",
            knownBadBundles: [], mousePoint: nil, windowTopAnchor: CGPoint(x: 7, y: 8))
        #expect(mode == .pill(CGPoint(x: rect.minX, y: rect.minY)))
    }
    @Test func pillAnchorFallsBackToWindowTop() {
        let mode = FallbackDetector.renderMode(
            caretRect: nil, hasSelectedRange: false, bundleID: "x",
            knownBadBundles: [], mousePoint: nil, windowTopAnchor: CGPoint(x: 7, y: 8))
        #expect(mode == .pill(CGPoint(x: 7, y: 8)))
    }
}
