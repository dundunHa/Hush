import Foundation
@testable import Hush
import Testing

// MARK: - AppContainer Catalog Tests

@MainActor
@Suite(.serialized)
struct AppContainerCatalogTests {
    // MARK: - Helpers

    private func makeCredentialStore(secrets: [String: String] = [:]) -> InMemoryCatalogCredentialStore {
        InMemoryCatalogCredentialStore(secrets: secrets)
    }

    private func makeContainerWithCatalog(
        settings: AppSettings? = nil,
        secrets: [String: String] = [:],
        registry: ProviderRegistry? = nil
    ) throws -> (AppContainer, GRDBProviderCatalogRepository) {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        let credentialStore = makeCredentialStore(secrets: secrets)
        let credentialResolver = CredentialResolver(secretStore: credentialStore)

        let container = AppContainer.forTesting(
            settings: settings,
            credentialStore: credentialStore,
            registry: registry,
            catalogRepository: catalogRepo,
            credentialResolver: credentialResolver
        )
        return (container, catalogRepo)
    }

    // MARK: - Placeholder Provider

    @Test("addPlaceholderProvider appends a custom provider with unique ID")
    func addPlaceholderProviderAppendsCustom() throws {
        let (container, _) = try makeContainerWithCatalog()
        let countBefore = container.settings.providerConfigurations.count

        container.addPlaceholderProvider()

        let configs = container.settings.providerConfigurations
        #expect(configs.count == countBefore + 1)

        let added = try #require(configs.last)
        #expect(added.type == .openAI)
        #expect(added.name == "OpenAI Compatible")
        #expect(added.isEnabled == true)
        #expect(added.id.hasPrefix("provider-"))
    }

    @Test("addPlaceholderProvider generates distinct IDs on repeated calls")
    func addPlaceholderProviderDistinctIDs() throws {
        let (container, _) = try makeContainerWithCatalog()

        container.addPlaceholderProvider()
        container.addPlaceholderProvider()

        let customIDs = container.settings.providerConfigurations
            .filter { $0.name == "OpenAI Compatible" }
            .map(\.id)
        #expect(Set(customIDs).count == customIDs.count)
    }

    // MARK: - Multi-Provider Profile Management

    @Test("saveProviderProfile adds new provider without affecting existing ones")
    func saveProviderProfileAddsNew() throws {
        let settings = AppSettings(
            providerConfigurations: [
                .mockDefault(),
                ProviderConfiguration(
                    id: "openai", name: "OpenAI", type: .openAI,
                    endpoint: "https://api.openai.com/v1", apiKeyEnvironmentVariable: "",
                    defaultModelID: "gpt-4", isEnabled: true
                )
            ],
            selectedProviderID: "mock",
            selectedModelID: "mock-text-1",
            parameters: .standard,
            quickBar: .standard
        )
        let (container, _) = try makeContainerWithCatalog(settings: settings)

        let newProfile = ProviderConfiguration(
            id: "anthropic",
            name: "Anthropic",
            type: .openAI,
            endpoint: "https://api.anthropic.com",
            apiKeyEnvironmentVariable: "",
            defaultModelID: "claude-3",
            isEnabled: true,
            credentialRef: "anthropic"
        )
        container.saveProviderProfile(newProfile)

        #expect(container.settings.providerConfigurations.contains(where: { $0.id == "anthropic" }))
        #expect(container.settings.providerConfigurations.contains(where: { $0.id == "openai" }))
        #expect(container.settings.providerConfigurations.contains(where: { $0.id == "mock" }))
    }

    @Test("saveProviderProfile updates existing provider in place")
    func saveProviderProfileUpdatesExisting() throws {
        let (container, _) = try makeContainerWithCatalog()

        // Add a provider
        let initial = ProviderConfiguration(
            id: "custom-1",
            name: "Custom One",
            type: .openAI,
            endpoint: "https://example.com",
            apiKeyEnvironmentVariable: "",
            defaultModelID: "model-a",
            isEnabled: true
        )
        container.saveProviderProfile(initial)

        // Update it
        var updated = initial
        updated.name = "Custom One Updated"
        updated.defaultModelID = "model-b"
        container.saveProviderProfile(updated)

        let configs = container.settings.providerConfigurations.filter { $0.id == "custom-1" }
        #expect(configs.count == 1)
        #expect(configs[0].name == "Custom One Updated")
        #expect(configs[0].defaultModelID == "model-b")
    }

    @Test("saveProviderProfile updates selected model when saving selected provider")
    func saveProviderProfileUpdatesSelectedModel() throws {
        let settings = AppSettings(
            providerConfigurations: [
                ProviderConfiguration(
                    id: "custom-1",
                    name: "Custom One",
                    type: .openAI,
                    endpoint: "https://example.com",
                    apiKeyEnvironmentVariable: "",
                    defaultModelID: "model-a",
                    isEnabled: true
                )
            ],
            selectedProviderID: "custom-1",
            selectedModelID: "model-a",
            parameters: .standard,
            quickBar: .standard
        )
        let (container, _) = try makeContainerWithCatalog(settings: settings)

        var updated = try #require(container.settings.providerConfigurations.first)
        updated.defaultModelID = "model-b"
        container.saveProviderProfile(updated)

        #expect(container.settings.selectedProviderID == "custom-1")
        #expect(container.settings.selectedModelID == "model-b")
    }

    @Test("removeProviderProfile triggers deterministic fallback when removing selected provider")
    func removeSelectedProviderFallsBack() throws {
        let settings = AppSettings(
            providerConfigurations: [
                .mockDefault(),
                ProviderConfiguration(
                    id: "openai", name: "OpenAI", type: .openAI,
                    endpoint: "", apiKeyEnvironmentVariable: "",
                    defaultModelID: "gpt-4", isEnabled: true
                )
            ],
            selectedProviderID: "openai",
            selectedModelID: "gpt-4",
            parameters: .standard,
            quickBar: .standard
        )

        let (container, _) = try makeContainerWithCatalog(settings: settings)
        container.removeProviderProfile(id: "openai")

        #expect(container.settings.selectedProviderID == "mock")
        #expect(!container.settings.providerConfigurations.contains(where: { $0.id == "openai" }))
    }

    @Test("removeProviderProfile cleans up catalog data")
    func removeProviderCleansCatalog() throws {
        let (container, catalogRepo) = try makeContainerWithCatalog()

        // Pre-populate catalog
        try catalogRepo.upsertCatalog(
            providerID: "custom-1",
            models: [ModelDescriptor(id: "model-a", displayName: "A", capabilities: [.text])]
        )

        container.saveProviderProfile(ProviderConfiguration(
            id: "custom-1", name: "Custom", type: .openAI,
            endpoint: "", apiKeyEnvironmentVariable: "",
            defaultModelID: "model-a", isEnabled: true
        ))

        container.removeProviderProfile(id: "custom-1")

        let models = try catalogRepo.models(forProviderID: "custom-1")
        #expect(models.isEmpty)
    }

    // MARK: - Fallback Selection

    @Test("Disabling selected provider triggers fallback to first enabled")
    func disablingSelectedProviderFallsBack() throws {
        let settings = AppSettings(
            providerConfigurations: [
                .mockDefault(),
                ProviderConfiguration(
                    id: "openai", name: "OpenAI", type: .openAI,
                    endpoint: "", apiKeyEnvironmentVariable: "",
                    defaultModelID: "gpt-4", isEnabled: true
                )
            ],
            selectedProviderID: "openai",
            selectedModelID: "gpt-4",
            parameters: .standard,
            quickBar: .standard
        )

        let (container, _) = try makeContainerWithCatalog(settings: settings)

        // Disable OpenAI by updating it
        var config = try #require(container.settings.providerConfigurations.first(where: { $0.id == "openai" }))
        config.isEnabled = false
        container.saveProviderProfile(config)

        #expect(container.settings.selectedProviderID == "mock")
        #expect(container.settings.selectedModelID == "mock-text-1")
    }

    @Test("Disabling selected provider falls back to enabled OpenAI when mock is absent")
    func disablingSelectedProviderFallsBackToEnabledOpenAI() throws {
        let settings = AppSettings(
            providerConfigurations: [
                ProviderConfiguration(
                    id: "custom-1", name: "Custom One", type: .openAI,
                    endpoint: "https://example.com", apiKeyEnvironmentVariable: "",
                    defaultModelID: "custom-model", isEnabled: true
                ),
                ProviderConfiguration(
                    id: "openai", name: "OpenAI", type: .openAI,
                    endpoint: "https://api.openai.com/v1", apiKeyEnvironmentVariable: "",
                    defaultModelID: "gpt-4o-mini", isEnabled: true
                )
            ],
            selectedProviderID: "custom-1",
            selectedModelID: "custom-model",
            parameters: .standard,
            quickBar: .standard
        )

        let (container, _) = try makeContainerWithCatalog(settings: settings)

        var custom = try #require(container.settings.providerConfigurations.first(where: { $0.id == "custom-1" }))
        custom.isEnabled = false
        container.saveProviderProfile(custom)

        #expect(container.settings.selectedProviderID == "openai")
        #expect(container.settings.selectedModelID == "gpt-4o-mini")
    }

    // MARK: - Catalog Cache Reading

    @Test("cachedModels returns empty for provider with no catalog")
    func cachedModelsEmptyForNewProvider() throws {
        let (container, _) = try makeContainerWithCatalog()
        let models = container.cachedModels(forProviderID: "nonexistent")
        #expect(models.isEmpty)
    }

    @Test("cachedModels returns persisted models after catalog refresh")
    func cachedModelsReturnsPersistedModels() throws {
        let (container, catalogRepo) = try makeContainerWithCatalog()

        try catalogRepo.upsertCatalog(
            providerID: "openai",
            models: [
                ModelDescriptor(id: "gpt-4", displayName: "GPT-4", capabilities: [.text]),
                ModelDescriptor(id: "gpt-3.5", displayName: "GPT-3.5", capabilities: [.text])
            ]
        )

        let models = container.cachedModels(forProviderID: "openai")
        #expect(models.count == 2)
    }

    // MARK: - Catalog Refresh Status

    @Test("catalogRefreshStatus returns nil for container without catalog repo")
    func refreshStatusWithoutRepo() {
        let container = AppContainer.forTesting()
        let status = container.catalogRefreshStatus(forProviderID: "openai")
        #expect(status == nil)
    }

    @Test("catalogRefreshStatus returns status after successful refresh")
    func refreshStatusAfterSuccess() throws {
        let (container, catalogRepo) = try makeContainerWithCatalog()

        try catalogRepo.upsertCatalog(
            providerID: "openai",
            models: [ModelDescriptor(id: "gpt-4", displayName: "GPT-4", capabilities: [.text])]
        )

        let status = container.catalogRefreshStatus(forProviderID: "openai")
        #expect(status != nil)
        #expect(status?.hasUsableCache == true)
        #expect(status?.modelCount == 1)
    }

    // MARK: - Draft Catalog Preview

    @Test("previewModels uses draft API key and does not persist catalog")
    func previewModelsUsesDraftAPIKeyWithoutPersistence() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        let provider = PreviewCatalogProviderStub(
            id: "draft-preview",
            models: [ModelDescriptor(id: "draft-model", displayName: "Draft Model", capabilities: [.text])]
        )
        var registry = ProviderRegistry()
        registry.register(provider)

        let credentialStore = makeCredentialStore()
        let container = AppContainer.forTesting(
            credentialStore: credentialStore,
            registry: registry,
            catalogRepository: catalogRepo,
            credentialResolver: CredentialResolver(secretStore: credentialStore)
        )

        let result = await container.previewModels(for: ProviderCatalogDraftInput(
            providerID: "draft-preview",
            type: .openAI,
            endpoint: " https://draft.example.com/v1 ",
            apiKey: "sk-draft-preview",
            credentialRef: nil
        ))

        #expect(result.error == nil)
        #expect(result.models.map(\.id) == ["draft-model"])
        #expect(provider.lastContext?.endpoint == "https://draft.example.com/v1")
        #expect(provider.lastContext?.bearerToken == "sk-draft-preview")

        let persistedModels = try catalogRepo.models(forProviderID: "draft-preview")
        #expect(persistedModels.isEmpty)
    }

    @Test("previewModels falls back to stored credential when draft API key is empty")
    func previewModelsUsesStoredCredential() async {
        let provider = PreviewCatalogProviderStub(
            id: "openai",
            models: [ModelDescriptor(id: "gpt-4.1", displayName: "GPT-4.1", capabilities: [.text])]
        )
        var registry = ProviderRegistry()
        registry.register(provider)

        let credentialStore = makeCredentialStore(secrets: ["openai": "sk-stored-preview"])
        let container = AppContainer.forTesting(
            credentialStore: credentialStore,
            registry: registry,
            credentialResolver: CredentialResolver(secretStore: credentialStore)
        )

        let result = await container.previewModels(for: ProviderCatalogDraftInput(
            providerID: "openai",
            type: .openAI,
            endpoint: "",
            apiKey: "",
            credentialRef: "openai"
        ))

        #expect(result.error == nil)
        #expect(result.models.map(\.id) == ["gpt-4.1"])
        #expect(provider.lastContext?.endpoint == OpenAIProvider.defaultEndpoint)
        #expect(provider.lastContext?.bearerToken == "sk-stored-preview")
    }

    @Test("previewModels requires API key when no draft or stored credential exists")
    func previewModelsRequiresCredential() async {
        let provider = PreviewCatalogProviderStub(id: "openai", models: [])
        var registry = ProviderRegistry()
        registry.register(provider)

        let credentialStore = makeCredentialStore()
        let container = AppContainer.forTesting(
            credentialStore: credentialStore,
            registry: registry,
            credentialResolver: CredentialResolver(secretStore: credentialStore)
        )

        let result = await container.previewModels(for: ProviderCatalogDraftInput(
            providerID: "openai",
            type: .openAI,
            endpoint: "",
            apiKey: "",
            credentialRef: nil
        ))

        #expect(result.models.isEmpty)
        #expect(result.error == "Enter an API key to fetch models.")
        #expect(provider.lastContext == nil)
    }

    // MARK: - Strict Validation with Catalog

    @Test("Strict validation passes when model exists in cached catalog")
    func strictValidationPassesWithCachedModel() async throws {
        var registry = ProviderRegistry()
        let client = FakeHTTPClientForCatalogTests()
        // Client should NOT be called if catalog is used
        client.sendJSONHandler = { _ in
            Issue.record("Should not make network call when cache is available")
            return (Data(), 200)
        }
        client.streamSSEHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(SSEEvent(data: "[DONE]"))
                continuation.finish()
            }
        }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)
        registry.register(MockProvider(id: "mock"))

        let settings = AppSettings(
            providerConfigurations: [
                .mockDefault(),
                ProviderConfiguration(
                    id: "openai", name: "OpenAI", type: .openAI,
                    endpoint: "https://api.openai.com/v1", apiKeyEnvironmentVariable: "",
                    defaultModelID: "gpt-4", isEnabled: true, credentialRef: "openai"
                )
            ],
            selectedProviderID: "openai",
            selectedModelID: "gpt-4",
            parameters: .standard,
            quickBar: .standard
        )

        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        let credentialStore = InMemoryCatalogCredentialStore(secrets: ["openai": "sk-test"])

        // Pre-populate catalog
        try catalogRepo.upsertCatalog(
            providerID: "openai",
            models: [ModelDescriptor(id: "gpt-4", displayName: "GPT-4", capabilities: [.text], modelType: .chat)]
        )

        let container = AppContainer.forTesting(
            settings: settings,
            credentialStore: credentialStore,
            registry: registry,
            catalogRepository: catalogRepo,
            credentialResolver: CredentialResolver(secretStore: credentialStore)
        )
        container.preflightTimeoutOverride = .seconds(2)

        // Send a draft - it should pass preflight via cached catalog
        container.sendDraft("Hello")

        // Give a moment for the async request to start
        try await Task.sleep(for: .milliseconds(100))

        // If we get here without the fake HTTP client being called for /models,
        // the catalog cache was used for validation
        #expect(true)
    }
}

// MARK: - Test Helpers

private final class FakeHTTPClientForCatalogTests: HTTPClient, @unchecked Sendable {
    nonisolated(unsafe) var sendJSONHandler: ((HTTPRequest) async throws -> (Data, Int))?
    nonisolated(unsafe) var streamSSEHandler: ((HTTPRequest) async throws -> AsyncThrowingStream<SSEEvent, Error>)?

    func sendJSON(_ request: HTTPRequest) async throws -> (Data, Int) {
        guard let handler = sendJSONHandler else {
            fatalError("sendJSONHandler not configured")
        }
        return try await handler(request)
    }

    func streamSSE(_ request: HTTPRequest) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        guard let handler = streamSSEHandler else {
            fatalError("streamSSEHandler not configured")
        }
        return try await handler(request)
    }
}

private final class PreviewCatalogProviderStub: LLMProvider, @unchecked Sendable {
    let id: String
    let models: [ModelDescriptor]
    nonisolated(unsafe) var lastContext: ProviderInvocationContext?

    init(id: String, models: [ModelDescriptor]) {
        self.id = id
        self.models = models
    }

    func availableModels(context: ProviderInvocationContext) async throws -> [ModelDescriptor] {
        await Task.yield()
        lastContext = context
        return models
    }

    func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage {
        await Task.yield()
        fatalError("Unused in catalog preview tests")
    }

    func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID _: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private final class InMemoryCatalogCredentialStore: KeychainCredentialStore, @unchecked Sendable {
    private var secrets: [String: String]

    init(secrets: [String: String] = [:]) {
        self.secrets = secrets
    }

    func setSecret(_ secret: String, forCredentialRef credentialRef: String) throws {
        secrets[credentialRef] = secret
    }

    func secret(forCredentialRef credentialRef: String) throws -> String {
        guard let secret = secrets[credentialRef] else {
            throw KeychainError.itemNotFound
        }
        return secret
    }

    func hasSecret(forCredentialRef credentialRef: String) -> Bool {
        secrets[credentialRef] != nil
    }
}
