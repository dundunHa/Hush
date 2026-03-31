import Foundation

// MARK: - Catalog Refresh Triggers

extension AppContainer {
    /// Triggers a catalog refresh for a provider. Non-blocking; runs asynchronously.
    func refreshCatalog(forProviderID providerID: String) {
        guard let service = catalogRefreshService else { return }
        guard let config = settings.providerConfigurations.first(where: { $0.id == providerID }) else { return }

        let provider = resolveProvider(for: config)

        let context = ProviderInvocationContext(
            endpoint: config.endpoint,
            bearerToken: config.normalizedAPIKey
        )

        catalogRefreshingProviderIDs.insert(providerID)
        catalogRefreshErrors.removeValue(forKey: providerID)

        Task {
            let result = await service.refresh(
                providerID: providerID,
                context: context,
                providerOverride: provider
            )
            self.catalogRefreshingProviderIDs.remove(providerID)
            switch result {
            case let .success(modelCount):
                self.statusMessage = "Refreshed \(modelCount) models for \(config.name)"
            case let .failure(error):
                self.statusMessage = "Catalog refresh failed: \(error)"
                self.catalogRefreshErrors[providerID] = error
            }
        }
    }

    /// Ensures a provider runtime is registered for the given configuration.
    /// Returns the registered provider instance.
    @discardableResult
    func ensureProviderRegistered(for config: ProviderConfiguration) -> any LLMProvider {
        if let existing = registry.provider(for: config.id) {
            return existing
        }
        let provider = makeProviderRuntime(id: config.id, type: config.type)
        registry.register(provider)
        return provider
    }

    /// Selects a deterministic fallback when the current default provider is unset.
    func selectDeterministicFallback() {
        selectDeterministicFallbackProvider()
    }
}

// MARK: - Provider Runtime & Catalog Helpers

extension AppContainer {
    func resolveProvider(for config: ProviderConfiguration) -> any LLMProvider {
        ensureProviderRegistered(for: config)
    }

    func previewProvider(for draft: ProviderCatalogDraftInput) -> any LLMProvider {
        if let provider = registry.provider(for: draft.providerID) {
            return provider
        }
        return makeProviderRuntime(id: draft.providerID, type: draft.type)
    }

    func makeProviderRuntime(id: String, type: ProviderType) -> any LLMProvider {
        switch type {
        case .openAI:
            OpenAIProvider(id: id)
        #if DEBUG
            case .mock:
                MockProvider(id: id)
        #endif
        }
    }

    func triggerCatalogRefreshIfNeeded(providerID: String) {
        guard let status = try? catalogRepository?.refreshStatus(forProviderID: providerID) else { return }
        if !status.hasUsableCache {
            refreshCatalog(forProviderID: providerID)
        }
    }

    func selectDeterministicFallbackProvider() {
        if let fallback = fallbackProviderConfiguration() {
            settings.selectedProviderID = fallback.id
            let fallbackModel = fallback.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackModel.isEmpty {
                settings.selectedModelID = fallbackModel
            }
        } else {
            settings.selectedProviderID = ""
            settings.selectedModelID = ""
        }
    }
}
