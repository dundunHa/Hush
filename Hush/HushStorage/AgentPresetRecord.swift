import Foundation
import GRDB

// MARK: - Agent Preset Record

/// GRDB-backed record for the `agentPresets` table.
/// Stores user-configured AI agent preset templates.
public nonisolated struct AgentPresetRecord: Codable, Sendable, Equatable {
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

    public init(
        id: String,
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
}

nonisolated extension AgentPresetRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "agentPresets"
}

// MARK: - Domain Conversion

public extension AgentPresetRecord {
    /// Converts this GRDB record into a domain `AgentPreset`.
    func toAgentPreset() -> AgentPreset {
        AgentPreset(
            id: id,
            name: name,
            systemPrompt: systemPrompt,
            providerID: providerID,
            modelID: modelID,
            temperature: temperature,
            topP: topP,
            topK: topK,
            maxTokens: maxTokens,
            thinkingBudget: thinkingBudget,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Creates a GRDB record from a domain `AgentPreset`.
    static func from(
        _ preset: AgentPreset,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) -> AgentPresetRecord {
        AgentPresetRecord(
            id: preset.id,
            name: preset.name,
            systemPrompt: preset.systemPrompt,
            providerID: preset.providerID,
            modelID: preset.modelID,
            temperature: preset.temperature,
            topP: preset.topP,
            topK: preset.topK,
            maxTokens: preset.maxTokens,
            thinkingBudget: preset.thinkingBudget,
            presencePenalty: preset.presencePenalty,
            frequencyPenalty: preset.frequencyPenalty,
            isDefault: preset.isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
