/// The complete set of persisted knobs a freshly built coordinator replays at startup:
/// one value, built in one place, applied in one call.
///
/// It lives here, in a dependency-free leaf, so both sides can name it without a new module
/// edge: SeerAppKit builds one from `AppSettings`, SeerCoordinator applies one via
/// `SuggestionCoordinator.apply(_:)`. Holding it in SeerAppKit instead would force
/// SeerCoordinator to depend on the UserDefaults layer to declare `apply`.
///
/// Every stored property is a `let` with no default, so adding a tunable is a compile error
/// at each site that builds a tuning — which is the point: the previous hand-maintained
/// replay could silently omit a knob, and neither `swift build` nor `swift test` would notice.
public struct CoordinatorTuning: Equatable, Sendable {
    public let enabled: Bool
    public let pausedBundles: Set<String>
    public let sampling: SamplingParams
    public let autoTemperature: Bool
    public let fontName: String?
    public let fontSize: Double
    public init(enabled: Bool,
                pausedBundles: Set<String>,
                sampling: SamplingParams,
                autoTemperature: Bool,
                fontName: String?,
                fontSize: Double) {
        self.enabled = enabled
        self.pausedBundles = pausedBundles
        self.sampling = sampling
        self.autoTemperature = autoTemperature
        self.fontName = fontName
        self.fontSize = fontSize
    }
}
