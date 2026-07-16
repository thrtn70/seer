public struct SamplingParams: Sendable, Equatable {
    public var temperature: Double
    public var topK: Int
    public var topP: Double
    public var maxTokens: Int
    public init(temperature: Double = 0.3, topK: Int = 40, topP: Double = 0.9, maxTokens: Int = 24) {
        self.temperature = temperature; self.topK = topK; self.topP = topP; self.maxTokens = maxTokens
    }
}
