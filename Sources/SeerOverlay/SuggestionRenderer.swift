import CoreGraphics
import SeerModel

/// Render-mode-agnostic seam: a coordinator (Phase 1D) drives `any SuggestionRenderer`
/// without knowing whether it holds an inline or pill renderer. Render-only in 1C —
/// no accept/commit (those are Phase 1D).
@MainActor
public protocol SuggestionRenderer: AnyObject {
    /// Update the streamed ghost text. The full accumulated string is passed on every
    /// token (matches the proven Phase-0 path). Empty/whitespace ⇒ the renderer hides itself.
    func update(text: String)

    /// Re-anchor to the latest geometry. Callers pass the RAW captured `RenderMode`;
    /// the renderer applies the 1C baseline calibration internally.
    func setPlacement(_ mode: RenderMode)

    /// Tear down on-screen content. Idempotent.
    func clear()
}
