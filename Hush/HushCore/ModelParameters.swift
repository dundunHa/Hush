import Foundation

public struct ModelParameters: Codable, Equatable, Sendable {
    public var temperature: Double
    public var topP: Double
    public var topK: Int?
    public var maxTokens: Int
    public var presencePenalty: Double
    public var frequencyPenalty: Double
    public var contextMessageLimit: Int?
    /// When `true`, omit temperature / topP / maxTokens / penalties from the
    /// API request so the remote model uses its own defaults.
    public var useModelDefaults: Bool

    public init(
        temperature: Double,
        topP: Double,
        topK: Int? = nil,
        maxTokens: Int,
        presencePenalty: Double,
        frequencyPenalty: Double,
        contextMessageLimit: Int? = nil,
        useModelDefaults: Bool = false
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.contextMessageLimit = contextMessageLimit
        self.useModelDefaults = useModelDefaults
    }

    // MARK: - Codable (backward-compatible decoding)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try c.decode(Double.self, forKey: .temperature)
        topP = try c.decode(Double.self, forKey: .topP)
        topK = try c.decodeIfPresent(Int.self, forKey: .topK)
        maxTokens = try c.decode(Int.self, forKey: .maxTokens)
        presencePenalty = try c.decode(Double.self, forKey: .presencePenalty)
        frequencyPenalty = try c.decode(Double.self, forKey: .frequencyPenalty)
        contextMessageLimit = try c.decodeIfPresent(Int.self, forKey: .contextMessageLimit)
        useModelDefaults = try c.decodeIfPresent(Bool.self, forKey: .useModelDefaults) ?? false
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
