import Foundation

public enum ProviderType: String, Codable, CaseIterable, Identifiable, Sendable {
    case mock
    case openAI
    case anthropic
    case ollama
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mock:
            "Mock"
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .ollama:
            "Ollama"
        case .custom:
            "Custom"
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

    public init(
        id: String,
        name: String,
        type: ProviderType,
        endpoint: String,
        apiKeyEnvironmentVariable: String,
        defaultModelID: String,
        isEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.endpoint = endpoint
        self.apiKeyEnvironmentVariable = apiKeyEnvironmentVariable
        self.defaultModelID = defaultModelID
        self.isEnabled = isEnabled
    }

    public static func mockDefault() -> ProviderConfiguration {
        ProviderConfiguration(
            id: "mock",
            name: "Local Mock",
            type: .mock,
            endpoint: "local://mock-provider",
            apiKeyEnvironmentVariable: "",
            defaultModelID: "mock-text-1",
            isEnabled: true
        )
    }
}

