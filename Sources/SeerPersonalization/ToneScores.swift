/// The three §7.4 style axes, each in [0,1].
public struct ToneScores: Sendable, Equatable {
    public let formality: Double
    public let warmth: Double
    public let brevity: Double
    public init(formality: Double, warmth: Double, brevity: Double) {
        self.formality = formality; self.warmth = warmth; self.brevity = brevity
    }
}

/// Activation thresholds (§7.6). `globalActivation` is a Phase-12 addition (recorded in the
/// parent-spec amendment); `appOverride` is the spec's ≥50.
public enum ProfileThresholds {
    public static let globalActivation = 20
    public static let appOverride = 50
}
