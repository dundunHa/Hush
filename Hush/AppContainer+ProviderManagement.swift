import Foundation

// MARK: - Settings Workspace

extension AppContainer {
    func openAISettingsSnapshot() -> OpenAISettingsSnapshot {
        let providerConfiguration = settings.providerConfigurations.first(where: { $0.id == OpenAISettingsInput.providerID })

        return OpenAISettingsSnapshot(
            endpoint: normalizeEndpoint(providerConfiguration?.endpoint ?? OpenAIProvider.defaultEndpoint),
            defaultModelID: providerConfiguration?.defaultModelID ?? "",
            isEnabled: providerConfiguration?.isEnabled ?? false,
            hasCredential: providerConfiguration?.hasPersistedAPIKey ?? false
        )
    }

    func saveOpenAISettings(_ input: OpenAISettingsInput) throws -> OpenAISettingsSnapshot {
        let normalizedModelID = input.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEnabled || !normalizedModelID.isEmpty else {
            throw OpenAISettingsSaveError.defaultModelRequired
        }

        let existingIndex = settings.providerConfigurations.firstIndex(where: { $0.id == OpenAISettingsInput.providerID })
        let existingConfiguration = existingIndex.map { settings.providerConfigurations[$0] }
        let trimmedAPIKey = input.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedAPIKey = trimmedAPIKey.isEmpty ? existingConfiguration?.apiKey ?? "" : trimmedAPIKey
        let hasCredential = !persistedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if input.isEnabled, !hasCredential {
            throw OpenAISettingsSaveError.credentialRequired
        }

        let nextConfiguration = ProviderConfiguration(
            id: OpenAISettingsInput.providerID,
            name: existingConfiguration?.name ?? "OpenAI",
            type: .openAI,
            endpoint: normalizeEndpoint(input.endpoint),
            apiKeyEnvironmentVariable: existingConfiguration?.apiKeyEnvironmentVariable ?? "",
            defaultModelID: normalizedModelID,
            isEnabled: input.isEnabled,
            apiKey: persistedAPIKey,
            credentialRef: existingConfiguration?.credentialRef,
            pinnedModelIDs: existingConfiguration?.pinnedModelIDs ?? []
        )

        if let index = existingIndex {
            settings.providerConfigurations[index] = nextConfiguration
        } else {
            settings.providerConfigurations.append(nextConfiguration)
        }

        // Persist to SQLite
        try? providerConfigRepository?.upsert(nextConfiguration)

        if settings.selectedProviderID == OpenAISettingsInput.providerID, input.isEnabled {
            settings.selectedModelID = normalizedModelID
        } else if !input.isEnabled, settings.selectedProviderID == OpenAISettingsInput.providerID {
            if let fallbackProvider = fallbackProviderConfiguration() {
                settings.selectedProviderID = fallbackProvider.id
                let fallbackModel = fallbackProvider.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fallbackModel.isEmpty {
                    settings.selectedModelID = fallbackModel
                }
            } else {
                settings.selectedProviderID = ""
                settings.selectedModelID = ""
            }
        }

        // Trigger catalog refresh when provider is enabled with credentials
        if input.isEnabled, hasCredential {
            refreshCatalog(forProviderID: OpenAISettingsInput.providerID)
        }

        return OpenAISettingsSnapshot(
            endpoint: nextConfiguration.endpoint,
            defaultModelID: nextConfiguration.defaultModelID,
            isEnabled: nextConfiguration.isEnabled,
            hasCredential: hasCredential
        )
    }

    // MARK: - Multi-Provider Profile Management

    /// Adds a new placeholder OpenAI-compatible provider using the same defaults as the settings UI.
    func addPlaceholderProvider() {
        let newID = "provider-\(UUID().uuidString.prefix(8))"
        let profile = ProviderConfiguration(
            id: newID,
            name: ProviderType.openAI.displayName,
            type: .openAI,
            endpoint: normalizeEndpoint(OpenAIProvider.defaultEndpoint),
            apiKeyEnvironmentVariable: "HUSH_API_KEY",
            defaultModelID: "",
            isEnabled: true
        )
        saveProviderProfile(profile)
    }

    /// Saves or updates a provider profile by its stable ID.
    func saveProviderProfile(_ profile: ProviderConfiguration) {
        let wasSelectedProvider = settings.selectedProviderID == profile.id

        if let index = settings.providerConfigurations.firstIndex(where: { $0.id == profile.id }) {
            settings.providerConfigurations[index] = profile
        } else {
            settings.providerConfigurations.append(profile)
        }

        // Persist to SQLite
        try? providerConfigRepository?.upsert(profile)

        if wasSelectedProvider {
            if !profile.isEnabled {
                selectDeterministicFallbackProvider()
            } else {
                let normalizedModel = profile.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalizedModel.isEmpty {
                    settings.selectedModelID = normalizedModel
                }
            }
        }
    }

    /// Sets a provider as the default (selected) provider.
    /// Automatically selects its default model.
    func setDefaultProvider(id: String) {
        guard let config = settings.providerConfigurations.first(where: { $0.id == id }) else { return }
        settings.selectedProviderID = id
        let model = config.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            settings.selectedModelID = model
        }
        triggerCatalogRefreshIfNeeded(providerID: id)
    }

    /// Removes a provider profile and cleans up its catalog cache.
    func removeProviderProfile(id: String) {
        settings.providerConfigurations.removeAll { $0.id == id }

        // Persist deletion to SQLite
        try? providerConfigRepository?.delete(id: id)

        // Clean up catalog cache (best-effort, no secrets involved)
        try? catalogRepository?.removeCatalog(forProviderID: id)

        // Deterministic fallback if removed provider was selected
        if settings.selectedProviderID == id {
            selectDeterministicFallbackProvider()
        }
    }

    /// Selects a provider and its default model, triggering catalog refresh if needed.
    func selectProvider(id: String) {
        guard let config = settings.providerConfigurations.first(where: { $0.id == id }) else { return }
        guard config.isEnabled else { return }

        settings.selectedProviderID = id

        // Try to use defaultModelID as initial selection
        let defaultModel = config.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !defaultModel.isEmpty {
            settings.selectedModelID = defaultModel
        }

        // Trigger catalog refresh if no usable cache exists
        triggerCatalogRefreshIfNeeded(providerID: id)
    }

    /// Returns cached catalog models for a provider, or empty array if unavailable.
    func cachedModels(forProviderID providerID: String) -> [ModelDescriptor] {
        (try? catalogRepository?.models(forProviderID: providerID)) ?? []
    }

    /// Returns the catalog refresh status for a provider.
    func catalogRefreshStatus(forProviderID providerID: String) -> ProviderCatalogRefreshStatus? {
        try? catalogRepository?.refreshStatus(forProviderID: providerID)
    }

    /// Resolves available models for a provider asynchronously.
    /// Uses cache if available; otherwise fetches from provider API and caches the result.
    /// Returns sorted models and whether they came from cache.
    func availableModels(forProviderID providerID: String) async -> (models: [ModelDescriptor], fromCache: Bool, error: String?) {
        guard let service = catalogRefreshService else {
            return ([], false, "Catalog service unavailable")
        }

        guard let config = settings.providerConfigurations.first(where: { $0.id == providerID }) else {
            return ([], false, "Provider not configured")
        }

        let provider = resolveProvider(for: config)

        let context = ProviderInvocationContext(
            endpoint: config.endpoint,
            bearerToken: config.normalizedAPIKey
        )

        let (models, fromCache) = await service.resolveModels(
            providerID: providerID,
            context: context,
            providerOverride: provider
        )

        let sortedModels = models.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        if sortedModels.isEmpty {
            return ([], fromCache, "Model catalog unavailable")
        }

        return (sortedModels, fromCache, nil)
    }

    /// Resolves model catalog data from the current draft provider settings without persisting it.
    func previewModels(for draft: ProviderCatalogDraftInput) async -> (models: [ModelDescriptor], error: String?) {
        let provider = previewProvider(for: draft)
        let trimmedAPIKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let bearerToken: String?
        if !trimmedAPIKey.isEmpty {
            bearerToken = trimmedAPIKey
        } else if let persistedAPIKey = draft.persistedAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !persistedAPIKey.isEmpty {
            bearerToken = persistedAPIKey
        } else {
            switch draft.type {
            case .openAI:
                return ([], "Enter an API key to fetch models.")
            #if DEBUG
                case .mock:
                    bearerToken = nil
            #endif
            }
        }

        let context = ProviderInvocationContext(
            endpoint: normalizedEndpoint(draft.endpoint, for: draft.type),
            bearerToken: bearerToken
        )

        do {
            let models = try await provider.availableModels(context: context)
            let sortedModels = models.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            if sortedModels.isEmpty {
                return ([], "Model catalog unavailable")
            }
            return (sortedModels, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    // MARK: - Agent Preset Management

    func fetchAgentPresets() -> [AgentPreset] {
        (try? agentPresetRepository?.fetchAll()) ?? []
    }

    func saveAgentPreset(_ preset: AgentPreset) {
        try? agentPresetRepository?.upsert(preset)
    }

    func deleteAgentPreset(id: String) {
        try? agentPresetRepository?.delete(id: id)
    }

    // MARK: - Prompt Template Management

    func fetchPromptTemplates() -> [PromptTemplate] {
        (try? promptTemplateRepository?.fetchAll()) ?? []
    }

    func savePromptTemplate(_ template: PromptTemplate) {
        try? promptTemplateRepository?.upsert(template)
    }

    func deletePromptTemplate(id: String) {
        try? promptTemplateRepository?.delete(id: id)
    }
}

// MARK: - Provider Helpers

extension AppContainer {
    func fallbackProviderConfiguration() -> ProviderConfiguration? {
        settings.providerConfigurations.first(where: { $0.isEnabled })
    }

    func normalizeEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? OpenAIProvider.defaultEndpoint : trimmed
    }

    func normalizedEndpoint(_ endpoint: String, for type: ProviderType) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
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
