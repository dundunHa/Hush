import Foundation

public struct AgentPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var systemPrompt: String
    public var providerID: String
    public var modelID: String
    public var temperature: Double
    public var topP: Double
    public var topK: Int?
    public var maxTokens: Int
    public var thinkingBudget: Int?
    public var presencePenalty: Double
    public var frequencyPenalty: Double
    public var isDefault: Bool
    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Init

    public init(
        id: String = UUID().uuidString,
        name: String,
        systemPrompt: String = "",
        providerID: String = "",
        modelID: String = "",
        temperature: Double = 0.7,
        topP: Double = 1.0,
        topK: Int? = nil,
        maxTokens: Int = 4096,
        thinkingBudget: Int? = nil,
        presencePenalty: Double = 0.0,
        frequencyPenalty: Double = 0.0,
        isDefault: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.thinkingBudget = thinkingBudget
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Public Interface

    public static func standard() -> AgentPreset {
        AgentPreset(
            name: "Default Agent",
            systemPrompt: "You are a helpful assistant.",
            temperature: 0.7,
            topP: 1.0,
            maxTokens: 4096,
            isDefault: true
        )
    }
}
