import Foundation
@testable import Hush
import Testing

@Suite("Provider Settings View Tests")
struct ProviderSettingsViewTests {
    @Test("Manual refresh requires save when provider is not persisted")
    func manualRefreshRequiresSaveForUnpersistedProvider() {
        let requiresSave = ProviderCatalogRefreshGate.requiresSave(
            persistedConfig: nil,
            draftType: .openAI,
            draftEndpoint: OpenAIProvider.defaultEndpoint,
            pendingAPIKey: ""
        )

        #expect(requiresSave)
    }

    @Test("Manual refresh requires save when endpoint draft differs")
    func manualRefreshRequiresSaveForDraftEndpoint() {
        let persistedConfig = ProviderConfiguration(
            id: "provider-1",
            name: "OpenAI Compatible",
            type: .openAI,
            endpoint: "https://api.example.com/v1",
            apiKeyEnvironmentVariable: "HUSH_API_KEY",
            defaultModelID: "gpt-4o-mini",
            isEnabled: true,
            credentialRef: "legacy-ref"
        )

        let requiresSave = ProviderCatalogRefreshGate.requiresSave(
            persistedConfig: persistedConfig,
            draftType: .openAI,
            draftEndpoint: "https://api.other.example.com/v1",
            pendingAPIKey: ""
        )

        #expect(requiresSave)
    }

    @Test("Manual refresh requires save when API key change is pending")
    func manualRefreshRequiresSaveForPendingAPIKey() {
        let persistedConfig = ProviderConfiguration(
            id: "provider-1",
            name: "OpenAI Compatible",
            type: .openAI,
            endpoint: "https://api.example.com/v1",
            apiKeyEnvironmentVariable: "HUSH_API_KEY",
            defaultModelID: "gpt-4o-mini",
            isEnabled: true,
            credentialRef: "legacy-ref"
        )

        let requiresSave = ProviderCatalogRefreshGate.requiresSave(
            persistedConfig: persistedConfig,
            draftType: .openAI,
            draftEndpoint: "https://api.example.com/v1",
            pendingAPIKey: "sk-unsaved"
        )

        #expect(requiresSave)
    }

    @Test("Manual refresh can reuse persisted provider state when draft is clean")
    func manualRefreshAllowsSavedProviderState() {
        let persistedConfig = ProviderConfiguration(
            id: "provider-1",
            name: "OpenAI Compatible",
            type: .openAI,
            endpoint: "https://api.example.com/v1",
            apiKeyEnvironmentVariable: "HUSH_API_KEY",
            defaultModelID: "gpt-4o-mini",
            isEnabled: true,
            credentialRef: "legacy-ref"
        )

        let requiresSave = ProviderCatalogRefreshGate.requiresSave(
            persistedConfig: persistedConfig,
            draftType: .openAI,
            draftEndpoint: " https://api.example.com/v1 ",
            pendingAPIKey: "   "
        )

        #expect(!requiresSave)
    }
}
