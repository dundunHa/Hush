import Foundation
@testable import Hush
import Testing

struct ProviderSettingsViewTests {
    private func makeCatalogModels() -> [ModelDescriptor] {
        [
            ModelDescriptor(id: "gpt-4.1", displayName: "GPT-4.1", capabilities: [.text]),
            ModelDescriptor(id: "gpt-4.1-mini", displayName: "GPT-4.1 Mini", capabilities: [.text]),
            ModelDescriptor(id: "claude-3.7-sonnet", displayName: "Claude 3.7 Sonnet", capabilities: [.text])
        ]
    }

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
            isEnabled: true
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
            isEnabled: true
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
            isEnabled: true
        )

        let usesDraftRefresh = ProviderCatalogRefreshGate.usesDraftRefresh(
            persistedConfig: persistedConfig,
            draftType: .openAI,
            draftEndpoint: " https://api.example.com/v1 ",
            pendingAPIKey: "   "
        )

        #expect(!usesDraftRefresh)
    }

    @Test("Filtered catalog models match model IDs and display names")
    func filteredCatalogModelsMatchQuery() {
        let filtered = ProviderCatalogSelectionLogic.filteredModels(
            makeCatalogModels(),
            searchText: "mini"
        )

        #expect(filtered.map(\.id) == ["gpt-4.1-mini"])
    }

    @Test("Select all filtered models keeps prior selection and appends filtered matches")
    func selectAllFilteredModelsKeepsExistingSelection() {
        let selection = ProviderCatalogSelectionLogic.selectingAllFilteredModels(
            currentSelection: ["gpt-4.1"],
            filteredModelIDs: ["gpt-4.1-mini", "claude-3.7-sonnet"]
        )

        #expect(selection == ["gpt-4.1", "gpt-4.1-mini", "claude-3.7-sonnet"])
    }

    @Test("Removing a selected catalog default clears the default model")
    func deselectingDefaultModelClearsDefault() {
        let nextDefault = ProviderCatalogSelectionLogic.defaultModelAfterCatalogSelectionChange(
            currentDefaultModelID: "gpt-4.1-mini",
            selectedCatalogModelIDs: ["gpt-4.1"],
            catalogModelIDs: makeCatalogModels().map(\.id)
        )

        #expect(nextDefault.isEmpty)
    }

    @Test("Manual default model IDs stay intact when catalog selection changes")
    func manualDefaultModelSurvivesCatalogSelectionChanges() {
        let catalogModelIDs = makeCatalogModels().map(\.id)
        let nextDefault = ProviderCatalogSelectionLogic.defaultModelAfterCatalogSelectionChange(
            currentDefaultModelID: "custom-model-id",
            selectedCatalogModelIDs: ["gpt-4.1"],
            catalogModelIDs: catalogModelIDs
        )
        let persistedSelection = ProviderCatalogSelectionLogic.normalizedModelIDs([
            "gpt-4.1",
            nextDefault
        ])

        #expect(nextDefault == "custom-model-id")
        #expect(persistedSelection == ["gpt-4.1", "custom-model-id"])
    }
}
