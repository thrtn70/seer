/// User-set per-axis tone pins (§7.7 as amended): nil = the axis stays learned. Values live
/// in UserDefaults (AppSettings), not the encrypted vault — they are preferences, not
/// learned data, so they survive profile resets and keychain-failure memory-only sessions.
/// Sanitized at construction (non-finite or out-of-[0,1] → nil) so a junk `defaults write`
/// can never poison snapshot equality (NaN breaks synthesized ==) or the descriptor bytes.
/// Named `neutral`, not `none`: `.none` would silently resolve to Optional.none in any
/// optional context.
public struct ToneOverrides: Sendable, Equatable {
    public let formality: Double?
    public let warmth: Double?
    public let brevity: Double?
    public init(formality: Double?, warmth: Double?, brevity: Double?) {
        self.formality = Self.sanitize(formality)
        self.warmth = Self.sanitize(warmth)
        self.brevity = Self.sanitize(brevity)
    }
    public static let neutral = ToneOverrides(formality: nil, warmth: nil, brevity: nil)
    private static func sanitize(_ v: Double?) -> Double? {
        guard let v, v.isFinite, (0.0...1.0).contains(v) else { return nil }
        return v == 0 ? 0.0 : v   // normalize -0.0: ==-equal pins must export identical bytes
    }
}
