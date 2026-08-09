import SeerModel

extension CoordinatorTuning {
    /// Read every persisted knob into one value — the single mapping from storage to runtime.
    ///
    /// Reads go through `AppSettings`' sanitizing getters, so hand-edited (`defaults write`)
    /// junk is already clamped before it reaches the coordinator. `topK`/`topP` have no
    /// Settings control and no persisted key: `SamplingParams`' defaults are the shipped values.
    public init(_ s: AppSettings) {
        self.init(enabled: s.enabled,
                  pausedBundles: s.pausedBundles,
                  sampling: SamplingParams(temperature: s.temperature, maxTokens: s.maxTokens),
                  autoTemperature: s.autoTemperature,
                  fontName: s.fontName,
                  fontSize: s.fontSize)
    }
}
