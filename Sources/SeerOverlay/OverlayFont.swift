import AppKit

/// What a future AX font read would yield (Phase 1D wires `kAXFontNameAttribute` /
/// `kAXFontSizeAttribute` here). Sendable — no AppKit types.
public struct FontDescriptorInput: Sendable, Equatable {
    public let name: String?
    public let size: Double?
    public init(name: String?, size: Double?) { self.name = name; self.size = size }
}

/// A resolved, sanitised font choice. Sendable — crosses isolation boundaries safely;
/// the non-Sendable `NSFont` is constructed from it on the main actor only.
public struct ResolvedFont: Sendable, Equatable {
    public let name: String?   // nil ⇒ system font
    public let size: Double
    public init(name: String?, size: Double) { self.name = name; self.size = size }
}

public enum OverlayFont {
    public static let defaultSize: Double = 13
    public static let minSize: Double = 6
    public static let maxSize: Double = 96

    /// Pure fallback policy: empty/nil name ⇒ system; nil/out-of-range size ⇒ default.
    public static func resolve(_ input: FontDescriptorInput) -> ResolvedFont {
        let name: String?
        if let n = input.name, !n.trimmingCharacters(in: .whitespaces).isEmpty {
            name = n
        } else {
            name = nil
        }
        let size: Double
        if let s = input.size, s >= minSize, s <= maxSize {
            size = s
        } else {
            size = defaultSize
        }
        return ResolvedFont(name: name, size: size)
    }

    /// Construct the AppKit font on the main actor from a Sendable `ResolvedFont`.
    @MainActor
    public static func nsFont(from resolved: ResolvedFont) -> NSFont {
        if let name = resolved.name, let font = NSFont(name: name, size: resolved.size) {
            return font
        }
        return .systemFont(ofSize: resolved.size)
    }
}
