import Foundation
import GRDB

// MARK: - Provider Configuration Record

/// GRDB-backed record for the `providerConfigurations` table.
/// Stores user-configured LLM provider settings.
public nonisolated struct ProviderConfigurationRecord: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var type: String
    public var endpoint: String
    public var apiKeyEnvironmentVariable: String
    public var defaultModelID: String
    public var isEnabled: Bool
    public var credentialRef: String?
    public var pinnedModelIDs: String // JSON-encoded [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        type: String,
        endpoint: String,
        apiKeyEnvironmentVariable: String = "",
        defaultModelID: String = "",
        isEnabled: Bool = false,
        credentialRef: String? = nil,
        pinnedModelIDs: String = "[]",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.endpoint = endpoint
        self.apiKeyEnvironmentVariable = apiKeyEnvironmentVariable
        self.defaultModelID = defaultModelID
        self.isEnabled = isEnabled
        self.credentialRef = credentialRef
        self.pinnedModelIDs = pinnedModelIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated extension ProviderConfigurationRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "providerConfigurations"
}

// MARK: - Domain Conversion

public extension ProviderConfigurationRecord {
    /// Converts this GRDB record into a domain `ProviderConfiguration`.
    func toProviderConfiguration() -> ProviderConfiguration {
        let decoder = JSONDecoder()

        let parsedPinnedModelIDs: [String] = (try? decoder.decode(
            [String].self,
            from: Data(pinnedModelIDs.utf8)
        )) ?? []

        let parsedType = ProviderType(rawValue: type) ?? .custom

        return ProviderConfiguration(
            id: id,
            name: name,
            type: parsedType,
            endpoint: endpoint,
            apiKeyEnvironmentVariable: apiKeyEnvironmentVariable,
            defaultModelID: defaultModelID,
            isEnabled: isEnabled,
            credentialRef: credentialRef,
            pinnedModelIDs: parsedPinnedModelIDs
        )
    }

    /// Creates a GRDB record from a domain `ProviderConfiguration`.
    static func from(
        _ config: ProviderConfiguration,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) -> ProviderConfigurationRecord {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let pinnedJSON = (try? String(data: encoder.encode(config.pinnedModelIDs), encoding: .utf8)) ?? "[]"

        return ProviderConfigurationRecord(
            id: config.id,
            name: config.name,
            type: config.type.rawValue,
            endpoint: config.endpoint,
            apiKeyEnvironmentVariable: config.apiKeyEnvironmentVariable,
            defaultModelID: config.defaultModelID,
            isEnabled: config.isEnabled,
            credentialRef: config.credentialRef,
            pinnedModelIDs: pinnedJSON,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
