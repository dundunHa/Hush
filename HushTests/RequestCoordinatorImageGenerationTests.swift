import Foundation
@testable import Hush
import Testing

@MainActor
struct RequestCoordinatorImageGenerationTests {
    @Test("Image-capable model uses non-streaming send path and persists attachment")
    func imageModelUsesNonStreamingPath() async throws {
        let provider = ImageOnlyProvider(id: "mock")
        let assetStore = CapturingMessageAssetStore()
        let db = try DatabaseManager.inMemory()
        let persistence = ChatPersistenceCoordinator(dbManager: db)
        let bootstrap = try persistence.bootstrap()

        var registry = ProviderRegistry()
        registry.register(provider)

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-image-1",
            parameters: .standard,
            quickBar: .standard
        )

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            persistence: persistence,
            messageAssetStore: assetStore,
            activeConversationId: bootstrap.conversationId
        )

        container.sendDraft("Draw a sunrise over the sea")
        try await waitForCompletion(container)

        #expect(await provider.sendCallCount == 1)
        #expect(await provider.sendStreamingCallCount == 0)
        #expect(await assetStore.materializeCallCount == 1)

        let assistant = try #require(container.messages.last(where: { $0.role == .assistant }))
        #expect(assistant.content == "Generated image.")
        #expect(assistant.attachments.count == 1)
        #expect(assistant.attachments[0].sourcePrompt == "Draw a sunrise over the sea")
        #expect(await assetStore.lastMessageID == assistant.id)
        #expect(container.requestCoordinatorFlushStateCountForTesting() == 0)

        let reloaded = try ChatPersistenceCoordinator(dbManager: db).bootstrap()
        let persistedAssistant = try #require(reloaded.messages.last(where: { $0.role == .assistant }))
        #expect(persistedAssistant.attachments == assistant.attachments)
    }

    @Test("Image request failure persists structured debug info on error message")
    func imageRequestFailurePersistsDebugInfo() async throws {
        let provider = FailingImageProvider(id: "mock")
        let db = try DatabaseManager.inMemory()
        let persistence = ChatPersistenceCoordinator(dbManager: db)
        let bootstrap = try persistence.bootstrap()

        var registry = ProviderRegistry()
        registry.register(provider)

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-image-1",
            parameters: .standard,
            quickBar: .standard
        )

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            persistence: persistence,
            activeConversationId: bootstrap.conversationId
        )

        container.sendDraft("Draw a failing image")
        try await waitForCompletion(container)

        let errorMessage = try #require(container.messages.last(where: { $0.content.hasPrefix("Error:") }))
        #expect(errorMessage.debugInfoJSON?.contains("\"responseStatusCode\" : 500") == true)
        #expect(errorMessage.debugInfoJSON?.contains("\"modelID\" : \"mock-image-1\"") == true)
        #expect(errorMessage.debugInfoJSON?.contains("convert_request_failed") == true)

        let reloaded = try ChatPersistenceCoordinator(dbManager: db).bootstrap()
        let persistedErrorMessage = try #require(reloaded.messages.last(where: { $0.content.hasPrefix("Error:") }))
        #expect(persistedErrorMessage.debugInfoJSON == errorMessage.debugInfoJSON)
    }

    private func waitForCompletion(_ container: AppContainer, timeout: Duration = .seconds(2)) async throws {
        let deadline = ContinuousClock.now + timeout
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(container.activeRequest == nil)
    }
}

private actor ImageOnlyProvider: LLMProvider {
    nonisolated let id: String
    private(set) var sendCallCount = 0
    private(set) var sendStreamingCallCount = 0

    init(id: String) {
        self.id = id
    }

    nonisolated func availableModels(context _: ProviderInvocationContext) async throws -> [ModelDescriptor] {
        await Task.yield()
        return [
            ModelDescriptor(
                id: "mock-image-1",
                displayName: "Mock Image",
                capabilities: [.image],
                modelType: .image,
                supportedInputs: [.text],
                supportedOutputs: [.image]
            )
        ]
    }

    nonisolated func send(
        messages: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ProviderResponse {
        await recordSendCall()
        let prompt = messages.last(where: { $0.role == .user })?.content ?? ""
        return ProviderResponse(
            text: "Generated image.",
            attachments: [
                .image(
                    ProviderImageAttachmentPayload(
                        data: requestCoordinatorOnePixelPNGData,
                        mimeType: "image/png",
                        pixelWidth: 1,
                        pixelHeight: 1,
                        sourcePrompt: prompt
                    )
                )
            ]
        )
    }

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        Task { await self.recordSendStreamingCall() }
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: requestID))
            continuation.yield(.completed(requestID: requestID))
            continuation.finish()
        }
    }

    private func recordSendCall() {
        sendCallCount += 1
    }

    private func recordSendStreamingCall() {
        sendStreamingCallCount += 1
    }
}

private actor FailingImageProvider: LLMProvider {
    nonisolated let id: String

    init(id: String) {
        self.id = id
    }

    nonisolated func availableModels(context _: ProviderInvocationContext) async throws -> [ModelDescriptor] {
        await Task.yield()
        return [
            ModelDescriptor(
                id: "mock-image-1",
                displayName: "Mock Image",
                capabilities: [.image],
                modelType: .image,
                supportedInputs: [.text],
                supportedOutputs: [.image]
            )
        ]
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ProviderResponse { // swiftlint:disable:this async_without_await
        throw ProviderRequestDebugFailure(
            providerID: id,
            message: "HTTP 500 from https://example.invalid/v1/images/generations",
            debugInfo: MessageDebugInfo(
                requestURL: "https://example.invalid/v1/images/generations",
                httpMethod: "POST",
                requestBodyJSON: #"{"model":"mock-image-1"}"#,
                responseStatusCode: 500,
                responseBodyPreview: #"{"error":{"code":"convert_request_failed"}}"#
            )
        )
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

private actor CapturingMessageAssetStore: MessageAssetStore {
    private(set) var materializeCallCount = 0
    private(set) var lastMessageID: UUID?

    func materialize(
        attachments: [ProviderResponseAttachment],
        conversationId _: String,
        messageId: UUID
    ) async throws -> [MessageAttachment] {
        await Task.yield()
        materializeCallCount += 1
        lastMessageID = messageId

        guard case let .image(payload) = try #require(attachments.first) else {
            Issue.record("Expected image attachment from provider")
            return []
        }

        return [
            MessageAttachment(
                id: UUID(),
                kind: .image,
                localRelativePath: "generated/\(messageId.uuidString).png",
                mimeType: payload.mimeType ?? "image/png",
                pixelWidth: payload.pixelWidth,
                pixelHeight: payload.pixelHeight,
                sha256: "stub-sha-\(messageId.uuidString)",
                sourcePrompt: payload.sourcePrompt,
                providerMetadataJSON: payload.providerMetadataJSON
            )
        ]
    }

    nonisolated func url(forRelativePath _: String) -> URL? {
        nil
    }

    func deleteAllAssets() async throws {}
}

private let requestCoordinatorOnePixelPNGData =
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jxM8AAAAASUVORK5CYII=") ?? Data()
