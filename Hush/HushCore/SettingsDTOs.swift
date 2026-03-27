import Foundation

struct OpenAISettingsSnapshot: Equatable {
    var endpoint: String
    var defaultModelID: String
    var isEnabled: Bool
    var hasCredential: Bool
}

struct OpenAISettingsInput: Equatable {
    static let providerID = "openai"

    var endpoint: String
    var defaultModelID: String
    var isEnabled: Bool
    var apiKey: String
}

struct ProviderCatalogDraftInput: Equatable {
    var providerID: String
    var type: ProviderType
    var endpoint: String
    var apiKey: String
    var persistedAPIKey: String?
}

enum OpenAISettingsSaveError: Error, Equatable {
    case defaultModelRequired
    case credentialRequired
}

extension OpenAISettingsSaveError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .defaultModelRequired:
            return "Default Model is required."
        case .credentialRequired:
            return "OpenAI is enabled but no API key is available. Enter an API key or keep it disabled."
        }
    }
}

struct DataStats {
    let databaseSizeBytes: UInt64
    let conversationCount: Int
    let messageCount: Int
}
