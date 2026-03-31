import Foundation

enum ProviderCatalogRefreshGate {
    static func usesDraftRefresh(
        persistedConfig: ProviderConfiguration?,
        draftType: ProviderType,
        draftEndpoint: String,
        pendingAPIKey: String
    ) -> Bool {
        guard let persistedConfig else { return true }
        guard draftType == persistedConfig.type else { return true }
        let draftNormalizedEndpoint = normalizedEndpoint(draftEndpoint, type: draftType)
        let persistedNormalizedEndpoint = normalizedEndpoint(
            persistedConfig.endpoint,
            type: persistedConfig.type
        )
        guard draftNormalizedEndpoint == persistedNormalizedEndpoint else {
            return true
        }
        return !pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func normalizedEndpoint(_ raw: String, type: ProviderType) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch type {
            case .openAI:
                return OpenAIProvider.defaultEndpoint
            #if DEBUG
                case .mock:
                    return "local://mock-provider"
            #endif
            }
        }
        return trimmed
    }
}

struct ProviderCatalogDraftSignature: Equatable {
    let type: ProviderType
    let normalizedEndpoint: String
}

enum ProviderCatalogSelectionLogic {
    static func filteredModels(
        _ models: [ModelDescriptor],
        searchText: String
    ) -> [ModelDescriptor] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return models }
        return models.filter { model in
            model.id.localizedCaseInsensitiveContains(trimmedSearch)
                || model.displayName.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    static func selectedCatalogModelIDs(
        from storedModelIDs: [String],
        catalogModels: [ModelDescriptor]
    ) -> [String] {
        let storedSelection = Set(normalizedModelIDs(storedModelIDs))
        return catalogModels.map(\.id).filter(storedSelection.contains)
    }

    static func selectingAllFilteredModels(
        currentSelection: [String],
        filteredModelIDs: [String]
    ) -> [String] {
        normalizedModelIDs(currentSelection + filteredModelIDs)
    }

    static func clearingCatalogSelection(
        currentSelection: [String],
        catalogModelIDs: [String]
    ) -> [String] {
        let catalogModelSet = Set(catalogModelIDs)
        return normalizedModelIDs(currentSelection.filter { !catalogModelSet.contains($0) })
    }

    static func defaultModelAfterCatalogSelectionChange(
        currentDefaultModelID: String,
        selectedCatalogModelIDs: [String],
        catalogModelIDs: [String]
    ) -> String {
        let normalizedDefault = currentDefaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDefault.isEmpty else { return "" }

        let catalogModelSet = Set(catalogModelIDs)
        guard catalogModelSet.contains(normalizedDefault) else {
            return normalizedDefault
        }

        return selectedCatalogModelIDs.contains(normalizedDefault) ? normalizedDefault : ""
    }

    static func isManualDefaultModelID(
        _ modelID: String,
        catalogModelIDs: [String]
    ) -> Bool {
        let normalizedDefault = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDefault.isEmpty else { return false }
        return !Set(catalogModelIDs).contains(normalizedDefault)
    }

    static func normalizedModelIDs(_ modelIDs: [String]) -> [String] {
        var uniqueIDs: [String] = []
        for rawID in modelIDs {
            let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !uniqueIDs.contains(trimmed) else { continue }
            uniqueIDs.append(trimmed)
        }
        return uniqueIDs
    }
}
