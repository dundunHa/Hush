import Foundation

public struct ModelParameters: Codable, Equatable, Sendable {
    public var temperature: Double
    public var topP: Double
    public var topK: Int?
    public var maxTokens: Int
    public var presencePenalty: Double
    public var frequencyPenalty: Double
    public var contextMessageLimit: Int?

    public init(
        temperature: Double,
        topP: Double,
        topK: Int? = nil,
        maxTokens: Int,
        presencePenalty: Double,
        frequencyPenalty: Double,
        contextMessageLimit: Int? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.contextMessageLimit = contextMessageLimit
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
