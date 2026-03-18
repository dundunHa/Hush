import Foundation
@testable import Hush
import Testing

// swiftlint:disable file_length

private final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
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

struct OpenAIProviderTests {
    private let endpoint = "https://api.openai.com/v1"

    @Test("availableModels returns parsed model descriptors")
    func availableModelsSuccess() async throws {
        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"},{"id":"gpt-3.5-turbo"}]}"#
        client.sendJSONHandler = { _ in
            (Data(json.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        let models = try await provider.availableModels(context: context)

        #expect(models.count == 2)
        #expect(models[0].id == "gpt-4")
        #expect(models[1].id == "gpt-3.5-turbo")
    }

    @Test("availableModels throws when bearer token is missing")
    func availableModelsMissingToken() async {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: nil)

        await #expect(throws: RequestError.self) {
            _ = try await provider.availableModels(context: context)
        }
    }

    @Test("sendStreaming yields started, delta, and completed events")
    func streamingChatSuccess() async throws {
        let client = FakeHTTPClient()
        client.streamSSEHandler = { _ in
            AsyncThrowingStream { continuation in
                let chunk = #"{"choices":[{"delta":{"content":"Hello"}}]}"#
                continuation.yield(SSEEvent(data: chunk))
                continuation.yield(SSEEvent(data: "[DONE]"))
                continuation.finish()
            }
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4",
            parameters: .standard,
            requestID: requestID,
            context: context
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 3)
        #expect(events[0] == .started(requestID: requestID))
        #expect(events[1] == .delta(requestID: requestID, text: "Hello"))
        #expect(events[2] == .completed(requestID: requestID))
    }

    @Test("sendStreaming yields failed event on non-2xx HTTP response")
    func streamingChatHTTPError() async throws {
        let client = FakeHTTPClient()
        client.streamSSEHandler = { request in
            throw HTTPError.nonSuccessStatus(statusCode: 429, body: "rate limited", url: request.url)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4",
            parameters: .standard,
            requestID: requestID,
            context: context
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let hasFailed = events.contains(where: {
            if case .failed = $0 { return true }
            return false
        })
        #expect(hasFailed)
    }

    @Test("Non-content deltas (role-only, tool metadata) are silently skipped")
    func nonContentDeltasIgnored() async throws {
        let client = FakeHTTPClient()
        client.streamSSEHandler = { _ in
            AsyncThrowingStream { continuation in
                let roleOnly = #"{"choices":[{"delta":{"role":"assistant"}}]}"#
                let nullContent = #"{"choices":[{"delta":{"content":null}}]}"#
                let emptyContent = #"{"choices":[{"delta":{"content":""}}]}"#
                let realContent = #"{"choices":[{"delta":{"content":"Real"}}]}"#

                continuation.yield(SSEEvent(data: roleOnly))
                continuation.yield(SSEEvent(data: nullContent))
                continuation.yield(SSEEvent(data: emptyContent))
                continuation.yield(SSEEvent(data: realContent))
                continuation.yield(SSEEvent(data: "[DONE]"))
                continuation.finish()
            }
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4",
            parameters: .standard,
            requestID: requestID,
            context: context
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 3)
        #expect(events[0] == .started(requestID: requestID))
        #expect(events[1] == .delta(requestID: requestID, text: "Real"))
        #expect(events[2] == .completed(requestID: requestID))
    }

    // MARK: - send (non-streaming)

    @Test("send throws remoteError because non-streaming is unsupported")
    func sendNonStreamingThrows() async {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")

        await #expect(throws: RequestError.self) {
            _ = try await provider.send(
                messages: [ChatMessage(role: .user, content: "Hi")],
                modelID: "gpt-4",
                parameters: .standard,
                context: context
            )
        }
    }

    // MARK: - sendStreaming token validation

    @Test("sendStreaming with nil token yields failed event")
    func streamingNilTokenFails() async throws {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: nil)
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4",
            parameters: .standard,
            requestID: requestID,
            context: context
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let hasFailed = events.contains(where: {
            if case .failed = $0 { return true }
            return false
        })
        #expect(hasFailed)
    }

    @Test("sendStreaming with empty string token yields failed event")
    func streamingEmptyTokenFails() async throws {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "")
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4",
            parameters: .standard,
            requestID: requestID,
            context: context
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let hasFailed = events.contains(where: {
            if case .failed = $0 { return true }
            return false
        })
        #expect(hasFailed)
    }

    @Test("availableModels throws when bearer token is empty string")
    func availableModelsEmptyToken() async {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "")

        await #expect(throws: RequestError.self) {
            _ = try await provider.availableModels(context: context)
        }
    }

    // MARK: - Endpoint normalization

    @Test("endpoint with /chat/completions suffix causes error")
    func endpointWithChatCompletionsSuffix() async throws {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let badEndpoint = "https://api.openai.com/v1/chat/completions"
        let context = ProviderInvocationContext(endpoint: badEndpoint, bearerToken: "sk-test")

        await #expect(throws: RequestError.self) {
            _ = try await provider.availableModels(context: context)
        }
    }

    @Test("endpoint with /models suffix causes error")
    func endpointWithModelsSuffix() async throws {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let badEndpoint = "https://api.openai.com/v1/models"
        let context = ProviderInvocationContext(endpoint: badEndpoint, bearerToken: "sk-test")

        await #expect(throws: RequestError.self) {
            _ = try await provider.availableModels(context: context)
        }
    }

    @Test("endpoint with trailing slash is normalized")
    func endpointTrailingSlashNormalized() async throws {
        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"}]}"#
        client.sendJSONHandler = { request in
            #expect(request.url == "https://api.openai.com/v1/models")
            return (Data(json.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(
            endpoint: "https://api.openai.com/v1/",
            bearerToken: "sk-test"
        )

        let models = try await provider.availableModels(context: context)
        #expect(models.count == 1)
    }

    @Test("empty endpoint falls back to default")
    func emptyEndpointUsesDefault() async throws {
        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"}]}"#
        client.sendJSONHandler = { request in
            #expect(request.url.starts(with: "https://api.openai.com/v1"))
            return (Data(json.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: "", bearerToken: "sk-test")

        let models = try await provider.availableModels(context: context)
        #expect(models.count == 1)
    }

    // MARK: - Normalized Metadata Mapping

    @Test("GPT model is classified as chat type")
    func gptModelTypeIsChat() {
        let model = OpenAIModel(id: "gpt-4o")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .chat)
    }

    @Test("Embedding model is classified as embedding type")
    func embeddingModelType() {
        let model = OpenAIModel(id: "text-embedding-3-small")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .embedding)
    }

    @Test("DALL-E model is classified as image type")
    func dalleModelType() {
        let model = OpenAIModel(id: "dall-e-3")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .image)
        #expect(descriptor.supportedOutputs.contains(.image))
    }

    @Test("Whisper model is classified as audio type")
    func whisperModelType() {
        let model = OpenAIModel(id: "whisper-1")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .audio)
    }

    @Test("o1 model is classified as reasoning type")
    func o1ModelType() {
        let model = OpenAIModel(id: "o1-preview")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .reasoning)
    }

    @Test("Unknown model ID yields unknown type with text defaults")
    func unknownModelDefaults() {
        let model = OpenAIModel(id: "some-custom-model")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .unknown)
        #expect(descriptor.supportedInputs == [.text])
        #expect(descriptor.supportedOutputs == [.text])
    }

    @Test("Vision-capable model includes image input modality")
    func visionModelInputModality() {
        let model = OpenAIModel(id: "gpt-4o-mini")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.supportedInputs.contains(.image))
    }

    @Test("ID-only payload produces valid normalized model entry")
    func idOnlyPayloadYieldsValidEntry() {
        let model = OpenAIModel(id: "gpt-4")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.id == "gpt-4")
        #expect(descriptor.displayName == "gpt-4")
        #expect(!descriptor.capabilities.isEmpty)
        #expect(!descriptor.supportedInputs.isEmpty)
        #expect(!descriptor.supportedOutputs.isEmpty)
    }

    @Test("Richer payload preserves owned_by in raw metadata")
    func richerPayloadPreservesRawMetadata() {
        let model = OpenAIModel(id: "gpt-4", ownedBy: "openai", created: 1_687_882_411)
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.rawMetadataJSON != nil)
        #expect(descriptor.rawMetadataJSON?.contains("openai") == true)
    }

    @Test("availableModels returns normalized metadata from richer payload")
    func availableModelsReturnsNormalizedMetadata() async throws {
        let client = FakeHTTPClient()
        let json = #"""
        {
          "data": [
            {
              "id": "gpt-4",
              "owned_by": "openai",
              "created": 1687882411,
              "modalities": ["text", "image"],
              "limits": { "max_output_tokens": 4096 },
              "deprecated": false
            }
          ]
        }
        """#
        client.sendJSONHandler = { _ in
            (Data(json.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        let models = try await provider.availableModels(context: context)

        #expect(models.count == 1)
        #expect(models[0].modelType == .chat)
        #expect(models[0].rawMetadataJSON != nil)
        #expect(models[0].rawMetadataJSON?.contains("\"modalities\"") == true)
        #expect(models[0].rawMetadataJSON?.contains("\"limits\"") == true)
        #expect(models[0].rawMetadataJSON?.contains("\"deprecated\"") == true)
    }
}

// MARK: - Catalog Refresh Service Tests

struct CatalogRefreshServiceTests {
    @Test("Successful refresh persists models and returns success")
    func successfulRefreshPersists() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()

        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"},{"id":"gpt-3.5-turbo"}]}"#
        client.sendJSONHandler = { _ in (Data(json.utf8), 200) }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let result = await service.refresh(
            providerID: "openai",
            context: ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")
        )

        #expect(result == .success(modelCount: 2))

        let models = try catalogRepo.models(forProviderID: "openai")
        #expect(models.count == 2)

        let status = try catalogRepo.refreshStatus(forProviderID: "openai")
        #expect(status.lastSuccessAt != nil)
        #expect(status.lastError == nil)
    }

    @Test("Failed refresh records error and preserves existing catalog")
    func failedRefreshRecordsError() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()

        // First, populate with a successful refresh
        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"}]}"#
        client.sendJSONHandler = { _ in (Data(json.utf8), 200) }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        _ = await service.refresh(
            providerID: "openai",
            context: ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")
        )

        // Now simulate a failure
        client.sendJSONHandler = { _ in throw HTTPError.nonSuccessStatus(statusCode: 500, body: "internal error", url: "test") }
        let failResult = await service.refresh(
            providerID: "openai",
            context: ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")
        )

        if case .failure = failResult {} else {
            Issue.record("Expected failure result")
        }

        // Previous models still available
        let models = try catalogRepo.models(forProviderID: "openai")
        #expect(models.count == 1)

        let status = try catalogRepo.refreshStatus(forProviderID: "openai")
        #expect(status.lastError != nil)
    }

    @Test("Refresh for unregistered provider returns failure")
    func unregisteredProviderFails() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        let registry = ProviderRegistry()

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let result = await service.refresh(
            providerID: "nonexistent",
            context: ProviderInvocationContext(endpoint: "", bearerToken: nil)
        )

        if case .failure = result {} else {
            Issue.record("Expected failure result")
        }
    }

    @Test("Concurrent refreshes for the same provider are coalesced")
    func concurrentRefreshesAreCoalesced() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()
        let provider = SlowCountingProvider(id: "mock")
        registry.register(provider)

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let context = ProviderInvocationContext(endpoint: "", bearerToken: nil)

        async let first: CatalogRefreshResult = service.refresh(providerID: "mock", context: context)
        async let second: CatalogRefreshResult = service.refresh(providerID: "mock", context: context)
        let (firstResult, secondResult) = await(first, second)

        #expect(firstResult == .success(modelCount: 1))
        #expect(secondResult == .success(modelCount: 1))
        #expect(await provider.availableModelsCallCount == 1)
    }

    @Test("resolveModels returns cached models without network call")
    func resolveModelsReturnsCachedModels() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()

        let client = FakeHTTPClient()
        var networkCallCount = 0
        let json = #"{"data":[{"id":"gpt-4"}]}"#
        client.sendJSONHandler = { _ in
            networkCallCount += 1
            return (Data(json.utf8), 200)
        }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)

        // Pre-populate cache
        try catalogRepo.upsertCatalog(providerID: "openai", models: [
            ModelDescriptor(id: "cached-model", displayName: "Cached Model", capabilities: [.text])
        ])

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let context = ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")

        let (models, fromCache) = await service.resolveModels(providerID: "openai", context: context)

        #expect(fromCache == true)
        #expect(models.count == 1)
        #expect(models[0].id == "cached-model")
        #expect(networkCallCount == 0)
    }

    @Test("resolveModels fetches live when cache is empty")
    func resolveModelsFetchesLiveWhenCacheEmpty() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()

        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"},{"id":"gpt-3.5-turbo"}]}"#
        client.sendJSONHandler = { _ in (Data(json.utf8), 200) }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let context = ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")

        let (models, fromCache) = await service.resolveModels(providerID: "openai", context: context)

        #expect(fromCache == false)
        #expect(models.count == 2)
    }

    @Test("resolveModels returns empty on fetch failure with empty cache")
    func resolveModelsReturnsEmptyOnFailure() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()

        let client = FakeHTTPClient()
        client.sendJSONHandler = { _ in throw HTTPError.nonSuccessStatus(statusCode: 500, body: "error", url: "test") }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let context = ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")

        let (models, fromCache) = await service.resolveModels(providerID: "openai", context: context)

        #expect(fromCache == false)
        #expect(models.isEmpty)
    }
}

private actor SlowCountingProvider: LLMProvider {
    nonisolated let id: String
    private(set) var availableModelsCallCount = 0

    init(id: String) {
        self.id = id
    }

    nonisolated func availableModels(context _: ProviderInvocationContext) async throws -> [ModelDescriptor] {
        await incrementCallCount()
        try await Task.sleep(for: .milliseconds(120))
        return [ModelDescriptor(id: "mock-text-1", displayName: "Mock Text 1", capabilities: [.text])]
    }

    private func incrementCallCount() {
        availableModelsCallCount += 1
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

// swiftlint:enable file_length
