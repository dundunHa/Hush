import Foundation

public struct ModelParameters: Codable, Equatable, Sendable {
    public var temperature: Double
    public var topP: Double
    public var maxTokens: Int
    public var presencePenalty: Double
    public var frequencyPenalty: Double

    public init(
        temperature: Double,
        topP: Double,
        maxTokens: Int,
        presencePenalty: Double,
        frequencyPenalty: Double
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
    }

    public static let standard = ModelParameters(
        temperature: 0.7,
        topP: 1.0,
        maxTokens: 1024,
        presencePenalty: 0.0,
        frequencyPenalty: 0.0
    )
}

