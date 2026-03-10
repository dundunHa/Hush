import Foundation

public enum ProviderType: String, Codable, CaseIterable, Identifiable, Sendable {
    #if DEBUG
        case mock
    #endif
    case openAI

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        #if DEBUG
            case .mock:
                "Mock"
        #endif
        case .openAI:
            "OpenAI"
        }
    }
}

public struct ProviderConfiguration: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var type: ProviderType
    public var endpoint: String
    public var apiKeyEnvironmentVariable: String
    public var defaultModelID: String
    public var isEnabled: Bool
    /// Persisted API key stored in the provider configuration table.
    /// This value is intentionally excluded from generic JSON encoding.
    public var apiKey: String

    /// Legacy credential reference retained for compatibility with older stored data.
    public var credentialRef: String?

    /// IDs of models the user has pinned/favorited for quick access.
    public var pinnedModelIDs: [String]

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id, name, type, endpoint, apiKeyEnvironmentVariable,
             defaultModelID, isEnabled, credentialRef, pinnedModelIDs
    }

    // MARK: - Init

    public init(
        id: String,
        name: String,
        type: ProviderType,
        endpoint: String,
        apiKeyEnvironmentVariable: String,
        defaultModelID: String,
        isEnabled: Bool,
        apiKey: String = "",
        credentialRef: String? = nil,
        pinnedModelIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.endpoint = endpoint
        self.apiKeyEnvironmentVariable = apiKeyEnvironmentVariable
        self.defaultModelID = defaultModelID
        self.isEnabled = isEnabled
        self.apiKey = apiKey
        self.credentialRef = credentialRef
        self.pinnedModelIDs = pinnedModelIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = (try? container.decode(ProviderType.self, forKey: .type)) ?? .openAI
        endpoint = try container.decode(String.self, forKey: .endpoint)
        apiKeyEnvironmentVariable = try container.decode(String.self, forKey: .apiKeyEnvironmentVariable)
        defaultModelID = try container.decode(String.self, forKey: .defaultModelID)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        apiKey = ""
        credentialRef = try container.decodeIfPresent(String.self, forKey: .credentialRef)
        pinnedModelIDs = try container.decodeIfPresent([String].self, forKey: .pinnedModelIDs) ?? []
    }

    // MARK: - Public Interface

    public var normalizedAPIKey: String? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var hasPersistedAPIKey: Bool {
        normalizedAPIKey != nil
    }

    #if DEBUG
        public static func mockDefault() -> ProviderConfiguration {
            ProviderConfiguration(
                id: "mock",
                name: "Local Mock",
                type: .mock,
                endpoint: "local://mock-provider",
                apiKeyEnvironmentVariable: "",
                defaultModelID: "mock-text-1",
                isEnabled: true,
                pinnedModelIDs: []
            )
        }
    #endif
}
