import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("RequestCoordinator Strict Validation Tests")
struct RequestCoordinatorStrictValidationTests {
    @Test("Selected model invalid for provider fails immediately without substitution")
    func invalidModelFailsImmediately() async throws {
        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "nonexistent-model",
            parameters: .standard,
            quickBar: .standard
        )

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            activeConversationId: "test-conv"
        )
        container.resetConversation()

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(container.activeRequest == nil)
        #expect(container.statusMessage.contains("not available"))

        let lastAssistant = container.messages.last(where: { $0.role == .assistant })
        #expect(lastAssistant?.content.contains("not available") == true)
    }

    @Test("Model preflight validation timeout fails request without starting generation")
    func preflightTimeoutFailsRequest() async throws {
        var registry = ProviderRegistry()
        registry.register(HangingPreflightProvider(id: "mock"))

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-text-1",
            parameters: .standard,
            quickBar: .standard
        )

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            activeConversationId: "test-conv"
        )
        container.resetConversation()
        container.preflightTimeoutOverride = .milliseconds(50)

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(container.activeRequest == nil)
        #expect(container.statusMessage.contains("timed out"))
    }

    @Test("Preflight failure prevents generation stream start")
    func preflightFailurePreventsGeneration() async throws {
        let provider = FailingPreflightProvider(id: "mock")
        var registry = ProviderRegistry()
        registry.register(provider)

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-text-1",
            parameters: .standard,
            quickBar: .standard
        )

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            activeConversationId: "test-conv"
        )
        container.resetConversation()

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(container.activeRequest == nil)

        let assistantMessages = container.messages.filter { $0.role == .assistant }
        let hasStreamedContent = assistantMessages.contains { msg in
            !msg.content.hasPrefix("Error:")
        }
        #expect(!hasStreamedContent)
        #expect(await provider.sendStreamingCallCount == 0)
    }

    @Test("Validation uses provider-scoped catalog cache when available")
    func validationUsesProviderScopedCatalog() async throws {
        let provider = NetworkCallTrackingProvider(id: "mock")
        var registry = ProviderRegistry()
        registry.register(provider)

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-text-1",
            parameters: .standard,
            quickBar: .standard
        )

        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)

        // Pre-populate catalog with the selected model
        try catalogRepo.upsertCatalog(
            providerID: "mock",
            models: [ModelDescriptor(id: "mock-text-1", displayName: "Mock Text 1", capabilities: [.text])]
        )

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            catalogRepository: catalogRepo,
            activeConversationId: "test-conv"
        )
        container.resetConversation()

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        // Preflight should have used catalog, NOT called availableModels
        #expect(await provider.availableModelsCallCount == 0)
    }

    @Test("Validation against provider-scoped catalog rejects model from other provider")
    func validationRejectsModelFromOtherProvider() async throws {
        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "other-provider-model",
            parameters: .standard,
            quickBar: .standard
        )

        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)

        // Catalog has a model for "mock" but NOT "other-provider-model"
        try catalogRepo.upsertCatalog(
            providerID: "mock",
            models: [ModelDescriptor(id: "mock-text-1", displayName: "Mock Text 1", capabilities: [.text])]
        )

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            catalogRepository: catalogRepo,
            activeConversationId: "test-conv"
        )
        container.resetConversation()

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(container.activeRequest == nil)
        #expect(container.statusMessage.contains("not available"))
    }

    @Test("Missing provider catalog falls back to live model discovery")
    func missingCatalogFallsBackToLiveDiscovery() async throws {
        let provider = NetworkCallTrackingProvider(id: "mock")
        var registry = ProviderRegistry()
        registry.register(provider)

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-text-1",
            parameters: .standard,
            quickBar: .standard
        )

        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        // Intentionally do not populate catalog rows - should fall back to live validation.

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            catalogRepository: catalogRepo,
            activeConversationId: "test-conv"
        )
        container.resetConversation()

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(container.activeRequest == nil)
        // When catalog is unavailable, it should fall back to live model discovery
        #expect(await provider.availableModelsCallCount == 1)
    }

    @Test("Coordinator-resolved invocation context is authoritative for non-mock providers")
    func coordinatorResolvedContextIsAuthoritative() async throws {
        let captureProvider = ContextCapturingProvider(id: "test-openai")
        var registry = ProviderRegistry()
        registry.register(captureProvider)

        let expectedEndpoint = "https://custom.api.example.com/v1"
        let expectedCredentialRef = "test-openai-cred-ref"
        let expectedToken = "sk-test-resolved-token-12345"

        let providerConfig = ProviderConfiguration(
            id: "test-openai",
            name: "Test OpenAI",
            type: .openAI,
            endpoint: expectedEndpoint,
            apiKeyEnvironmentVariable: "",
            defaultModelID: "capture-model-1",
            isEnabled: true,
            credentialRef: expectedCredentialRef
        )

        let settings = AppSettings(
            providerConfigurations: [providerConfig],
            selectedProviderID: "test-openai",
            selectedModelID: "capture-model-1",
            parameters: .standard,
            quickBar: .standard
        )

        let stubKeychain = StubKeychainSecretStore(secrets: [
            expectedCredentialRef: expectedToken
        ])
        let credentialResolver = CredentialResolver(secretStore: stubKeychain)

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            activeConversationId: "test-conv",
            credentialResolver: credentialResolver
        )
        container.resetConversation()

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        let capturedContext = await captureProvider.capturedContext
        #expect(capturedContext != nil)
        #expect(capturedContext?.endpoint == expectedEndpoint)
        #expect(capturedContext?.bearerToken == expectedToken)
    }
}

// MARK: - Test Helpers

private actor HangingPreflightProvider: LLMProvider {
    nonisolated let id: String

    init(id: String) {
        self.id = id
    }

    nonisolated func availableModels(context _: ProviderInvocationContext) async throws -> [ModelDescriptor] {
        try await Task.sleep(for: .seconds(3600))
        return []
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage { // swiftlint:disable:this async_without_await
        ChatMessage(role: .assistant, content: "unused")
    }

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: requestID))
            continuation.yield(.completed(requestID: requestID))
            continuation.finish()
        }
    }
}

private actor FailingPreflightProvider: LLMProvider {
    nonisolated let id: String
    private(set) var sendStreamingCallCount = 0

    init(id: String) {
        self.id = id
    }

    nonisolated func availableModels(
        context _: ProviderInvocationContext
    ) async throws -> [ModelDescriptor] { // swiftlint:disable:this async_without_await
        throw RequestError.remoteError(provider: "mock", message: "Simulated preflight failure")
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage { // swiftlint:disable:this async_without_await
        ChatMessage(role: .assistant, content: "unused")
    }

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        Task { await self.incrementStreamingCount() }
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: requestID))
            continuation.yield(.completed(requestID: requestID))
            continuation.finish()
        }
    }

    private func incrementStreamingCount() {
        sendStreamingCallCount += 1
    }
}

private actor ContextCapturingProvider: LLMProvider {
    nonisolated let id: String
    private(set) var capturedContext: ProviderInvocationContext?

    init(id: String) {
        self.id = id
    }

    nonisolated func availableModels(context: ProviderInvocationContext) async throws -> [ModelDescriptor] {
        await recordContext(context)
        return [
            ModelDescriptor(
                id: "capture-model-1",
                displayName: "Capture Model",
                capabilities: [.text]
            )
        ]
    }

    private func recordContext(_ context: ProviderInvocationContext) {
        capturedContext = context
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage { // swiftlint:disable:this async_without_await
        ChatMessage(role: .assistant, content: "unused")
    }

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: requestID))
            continuation.yield(.delta(requestID: requestID, text: "captured"))
            continuation.yield(.completed(requestID: requestID))
            continuation.finish()
        }
    }
}

private struct StubKeychainSecretStore: KeychainSecretStore {
    let secrets: [String: String]

    func secret(forCredentialRef credentialRef: String) throws -> String {
        guard let value = secrets[credentialRef] else {
            throw KeychainError.itemNotFound
        }
        return value
    }
}

/// Mock provider that tracks whether availableModels was called.
private actor NetworkCallTrackingProvider: LLMProvider {
    nonisolated let id: String
    private(set) var availableModelsCallCount = 0

    init(id: String) {
        self.id = id
    }

    nonisolated func availableModels(
        context _: ProviderInvocationContext
    ) async throws -> [ModelDescriptor] {
        await incrementAvailableModelsCount()
        return [
            ModelDescriptor(id: "mock-text-1", displayName: "Mock Text 1", capabilities: [.text])
        ]
    }

    private func incrementAvailableModelsCount() {
        availableModelsCallCount += 1
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage { // swiftlint:disable:this async_without_await
        ChatMessage(role: .assistant, content: "tracked")
    }

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: requestID))
            continuation.yield(.delta(requestID: requestID, text: "tracked"))
            continuation.yield(.completed(requestID: requestID))
            continuation.finish()
        }
    }
}
