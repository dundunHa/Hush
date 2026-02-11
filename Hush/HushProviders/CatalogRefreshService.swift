import Foundation
import os

private let logger = Logger(subsystem: "com.hush.app", category: "CatalogRefresh")

// MARK: - Catalog Refresh Result

/// Outcome of a provider catalog refresh attempt.
public enum CatalogRefreshResult: Sendable, Equatable {
    case success(modelCount: Int)
    case failure(error: String)
}

// MARK: - Catalog Refresh Service

/// Coordinates provider model discovery with catalog persistence.
/// Bridges `LLMProvider.availableModels` → `ProviderCatalogRepository`.
public actor CatalogRefreshService {
    private let catalogRepository: any ProviderCatalogRepository
    private let registry: ProviderRegistry
    private var inFlightRefreshes: [String: Task<CatalogRefreshResult, Never>] = [:]

    public init(
        catalogRepository: any ProviderCatalogRepository,
        registry: ProviderRegistry
    ) {
        self.catalogRepository = catalogRepository
        self.registry = registry
    }

    public func refresh(
        providerID: String,
        context: ProviderInvocationContext,
        providerOverride: (any LLMProvider)? = nil
    ) async -> CatalogRefreshResult {
        if let inFlight = inFlightRefreshes[providerID] {
            return await inFlight.value
        }

        let resolvedProvider = providerOverride ?? registry.provider(for: providerID)

        logger.notice("Starting catalog refresh for provider: \(providerID), endpoint: \(context.endpoint)")

        let task = Task<CatalogRefreshResult, Never> { [catalogRepository] in
            guard let provider = resolvedProvider else {
                let error = "Provider not registered: \(providerID)"
                logger.error("Catalog refresh failed: \(error)")
                try? catalogRepository.recordRefreshFailure(providerID: providerID, error: error)
                return .failure(error: error)
            }

            do {
                let models = try await provider.availableModels(context: context)
                logger.notice("Catalog refresh succeeded for \(providerID): \(models.count) models")
                try catalogRepository.upsertCatalog(providerID: providerID, models: models)
                return .success(modelCount: models.count)
            } catch {
                let errorMessage = error.localizedDescription
                logger.error("Catalog refresh failed for \(providerID): \(errorMessage)")
                try? catalogRepository.recordRefreshFailure(providerID: providerID, error: errorMessage)
                return .failure(error: errorMessage)
            }
        }

        inFlightRefreshes[providerID] = task
        defer { inFlightRefreshes[providerID] = nil }
        return await task.value
    }

    /// Resolves available models for a provider, using cache if available or fetching live.
    /// Returns cached models immediately if present; otherwise performs a live fetch and caches the result.
    public func resolveModels(
        providerID: String,
        context: ProviderInvocationContext,
        providerOverride: (any LLMProvider)? = nil
    ) async -> (models: [ModelDescriptor], fromCache: Bool) {
        // Try cache first (low-latency path)
        if let cached = try? catalogRepository.models(forProviderID: providerID), !cached.isEmpty {
            return (cached, true)
        }

        // No cache - perform live fetch
        let result = await refresh(
            providerID: providerID,
            context: context,
            providerOverride: providerOverride
        )

        switch result {
        case .success:
            let models = (try? catalogRepository.models(forProviderID: providerID)) ?? []
            return (models, false)
        case .failure:
            return ([], false)
        }
    }
}
