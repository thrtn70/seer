import CoreGraphics

/// How a suggestion is presented for a captured field.
public enum RenderMode: Sendable, Equatable {
    /// Ghost text inline at the caret rect (screen coords).
    case inline(CGRect)
    /// Floating pill anchored at a screen point (caret unavailable).
    case pill(CGPoint)
}
