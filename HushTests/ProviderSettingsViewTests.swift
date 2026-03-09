import Foundation
@testable import Hush
import Testing

@Suite("Provider Settings View Tests")
struct ProviderSettingsViewTests {
    @Test("Manual refresh uses draft mode when provider is not persisted")
    func manualRefreshUsesDraftModeForUnpersistedProvider() {
        let usesDraftRefresh = ProviderCatalogRefreshGate.usesDraftRefresh(
            persistedConfig: nil,
            draftType: .openAI,
            draftEndpoint: OpenAIProvider.defaultEndpoint,
            pendingAPIKey: ""
        )

        #expect(usesDraftRefresh)
    }

    @Test("Manual refresh uses draft mode when endpoint draft differs")
    func manualRefreshUsesDraftModeForDraftEndpoint() {
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

        let usesDraftRefresh = ProviderCatalogRefreshGate.usesDraftRefresh(
            persistedConfig: persistedConfig,
            draftType: .openAI,
            draftEndpoint: "https://api.other.example.com/v1",
            pendingAPIKey: ""
        )

        #expect(usesDraftRefresh)
    }

    @Test("Manual refresh uses draft mode when API key change is pending")
    func manualRefreshUsesDraftModeForPendingAPIKey() {
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

        let usesDraftRefresh = ProviderCatalogRefreshGate.usesDraftRefresh(
            persistedConfig: persistedConfig,
            draftType: .openAI,
            draftEndpoint: "https://api.example.com/v1",
            pendingAPIKey: "sk-unsaved"
        )

        #expect(usesDraftRefresh)
    }

    @Test("Manual refresh can reuse persisted provider state when draft is clean")
    func manualRefreshCanUsePersistedProviderState() {
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

        let usesDraftRefresh = ProviderCatalogRefreshGate.usesDraftRefresh(
            persistedConfig: persistedConfig,
            draftType: .openAI,
            draftEndpoint: " https://api.example.com/v1 ",
            pendingAPIKey: "   "
        )

        #expect(!usesDraftRefresh)
    }
}
