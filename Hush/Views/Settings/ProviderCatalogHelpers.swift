import SwiftUI

extension ProviderSettingsView {
    func normalizedModelIDs(_ modelIDs: [String]) -> [String] {
        ProviderCatalogSelectionLogic.normalizedModelIDs(modelIDs)
    }

    func currentCatalogDraftSignature() -> ProviderCatalogDraftSignature {
        ProviderCatalogDraftSignature(
            type: providerType,
            normalizedEndpoint: ProviderCatalogRefreshGate.normalizedEndpoint(endpoint, type: providerType)
        )
    }

    func persistedConfig(for providerID: String) -> ProviderConfiguration? {
        container.settings.providerConfigurations.first(where: { $0.id == providerID })
    }

    func editorProviderID(for target: ProviderEditorTarget) -> String {
        switch target {
        case let .existing(providerID):
            return providerID
        case .new:
            return "__new__"
        }
    }

    func usesDraftRefresh(for providerID: String) -> Bool {
        ProviderCatalogRefreshGate.usesDraftRefresh(
            persistedConfig: persistedConfig(for: providerID),
            draftType: providerType,
            draftEndpoint: endpoint,
            pendingAPIKey: apiKeyToSave
        )
    }

    func shouldDisplayDraftCatalog() -> Bool {
        guard draftCatalogSignature == currentCatalogDraftSignature() else {
            return false
        }
        return isDraftCatalogRefreshing || draftCatalogError != nil || !draftCatalogModels.isEmpty
    }

    func visibleCatalogModels(for providerID: String) -> [ModelDescriptor] {
        let models = shouldDisplayDraftCatalog()
            ? draftCatalogModels
            : container.cachedModels(forProviderID: providerID)
        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    func visibleCatalogRefreshError(for providerID: String) -> String? {
        shouldDisplayDraftCatalog()
            ? draftCatalogError
            : container.catalogRefreshErrors[providerID]
    }

    func isCatalogRefreshing(for providerID: String) -> Bool {
        shouldDisplayDraftCatalog()
            ? isDraftCatalogRefreshing
            : container.catalogRefreshingProviderIDs.contains(providerID)
    }

    func resetDraftCatalogState() {
        draftCatalogModels = []
        draftCatalogError = nil
        draftCatalogSignature = nil
        isDraftCatalogRefreshing = false
    }

    var normalizedDraftDefaultModelID: String {
        defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func filteredCatalogModels(_ models: [ModelDescriptor]) -> [ModelDescriptor] {
        ProviderCatalogSelectionLogic.filteredModels(models, searchText: modelSearchText)
    }

    func selectedCatalogModelIDs(for models: [ModelDescriptor]) -> [String] {
        ProviderCatalogSelectionLogic.selectedCatalogModelIDs(
            from: pinnedModelIDs,
            catalogModels: models
        )
    }

    func catalogDefaultSelection(for models: [ModelDescriptor]) -> String {
        let selectedModelIDs = selectedCatalogModelIDs(for: models)
        return selectedModelIDs.contains(normalizedDraftDefaultModelID) ? normalizedDraftDefaultModelID : ""
    }

    func isUsingManualDefaultModelID(for models: [ModelDescriptor]) -> Bool {
        ProviderCatalogSelectionLogic.isManualDefaultModelID(
            normalizedDraftDefaultModelID,
            catalogModelIDs: models.map(\.id)
        )
    }

    func applyCatalogSelection(_ selectedModelIDs: [String], allModels: [ModelDescriptor]) {
        let normalizedSelection = normalizedModelIDs(selectedModelIDs)
        let reconciledDefaultModelID = ProviderCatalogSelectionLogic.defaultModelAfterCatalogSelectionChange(
            currentDefaultModelID: normalizedDraftDefaultModelID,
            selectedCatalogModelIDs: normalizedSelection,
            catalogModelIDs: allModels.map(\.id)
        )

        pinnedModelIDs = normalizedSelection
        defaultModelID = reconciledDefaultModelID
    }

    func toggleSelectedCatalogModel(_ modelID: String, allModels: [ModelDescriptor]) {
        let currentSelection = selectedCatalogModelIDs(for: allModels)
        let nextSelection: [String]
        if currentSelection.contains(modelID) {
            nextSelection = currentSelection.filter { $0 != modelID }
        } else {
            nextSelection = currentSelection + [modelID]
        }
        applyCatalogSelection(nextSelection, allModels: allModels)
    }

    func selectAllFilteredCatalogModels(
        filteredModels: [ModelDescriptor],
        allModels: [ModelDescriptor]
    ) {
        let nextSelection = ProviderCatalogSelectionLogic.selectingAllFilteredModels(
            currentSelection: selectedCatalogModelIDs(for: allModels),
            filteredModelIDs: filteredModels.map(\.id)
        )
        applyCatalogSelection(nextSelection, allModels: allModels)
    }

    func clearSelectedCatalogModels(_ allModels: [ModelDescriptor]) {
        let nextSelection = ProviderCatalogSelectionLogic.clearingCatalogSelection(
            currentSelection: selectedCatalogModelIDs(for: allModels),
            catalogModelIDs: allModels.map(\.id)
        )
        applyCatalogSelection(nextSelection, allModels: allModels)
    }

    func currentEditingConfiguration(for target: ProviderEditorTarget) -> ProviderConfiguration {
        switch target {
        case .new:
            return ProviderConfiguration(
                id: editorProviderID(for: target),
                name: providerName,
                type: providerType,
                endpoint: endpoint,
                apiKeyEnvironmentVariable: "HUSH_API_KEY",
                defaultModelID: defaultModelID,
                isEnabled: isEnabled,
                pinnedModelIDs: pinnedModelIDs
            )
        case let .existing(providerID):
            return providers.first(where: { $0.id == providerID })
                ?? ProviderConfiguration(
                    id: providerID,
                    name: providerName,
                    type: providerType,
                    endpoint: endpoint,
                    apiKeyEnvironmentVariable: "",
                    defaultModelID: defaultModelID,
                    isEnabled: isEnabled,
                    pinnedModelIDs: pinnedModelIDs
                )
        }
    }
}
