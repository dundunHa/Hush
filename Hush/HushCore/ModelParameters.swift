import Foundation

public enum ModelReasoningEffort: String, Codable, CaseIterable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
}

public struct ModelParameters: Codable, Equatable, Sendable {
    public var temperature: Double
    public var topP: Double
    public var topK: Int?
    public var maxTokens: Int
    public var presencePenalty: Double
    public var frequencyPenalty: Double
    public var contextMessageLimit: Int?
    /// When `true`, omit temperature / topP / max token / penalties from the
    /// API request so the remote model uses its own defaults.
    public var useModelDefaults: Bool
    /// OpenAI reasoning effort is independent from temperature / topP / max token.
    public var reasoningEffort: ModelReasoningEffort?

    public init(
        temperature: Double,
        topP: Double,
        topK: Int? = nil,
        maxTokens: Int,
        presencePenalty: Double,
        frequencyPenalty: Double,
        contextMessageLimit: Int? = nil,
        useModelDefaults: Bool = false,
        reasoningEffort: ModelReasoningEffort? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.contextMessageLimit = contextMessageLimit
        self.useModelDefaults = useModelDefaults
        self.reasoningEffort = reasoningEffort
    }

    // MARK: - Codable (backward-compatible decoding)

    public init(from decoder: Decoder) throws {
        let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try keyedContainer.decode(Double.self, forKey: .temperature)
        topP = try keyedContainer.decode(Double.self, forKey: .topP)
        topK = try keyedContainer.decodeIfPresent(Int.self, forKey: .topK)
        maxTokens = try keyedContainer.decode(Int.self, forKey: .maxTokens)
        presencePenalty = try keyedContainer.decode(Double.self, forKey: .presencePenalty)
        frequencyPenalty = try keyedContainer.decode(Double.self, forKey: .frequencyPenalty)
        contextMessageLimit = try keyedContainer.decodeIfPresent(Int.self, forKey: .contextMessageLimit)
        useModelDefaults = try keyedContainer.decodeIfPresent(Bool.self, forKey: .useModelDefaults) ?? false
        reasoningEffort = try keyedContainer.decodeIfPresent(ModelReasoningEffort.self, forKey: .reasoningEffort)
    }

    public static let standard = ModelParameters(
        temperature: 0.7,
        topP: 1.0,
        topK: nil,
        maxTokens: 4096,
        presencePenalty: 0.0,
        frequencyPenalty: 0.0,
        contextMessageLimit: 10
    )
}
