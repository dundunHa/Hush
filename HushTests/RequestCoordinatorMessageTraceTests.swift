import Foundation
@testable import Hush
import Testing

@MainActor
struct RequestCoordinatorMessageTraceTests {
    @Test("Streaming request trace is synchronized to user and assistant messages")
    func streamingTraceSyncsAcrossMessagePair() async throws {
        let provider = DebugStreamingProvider(id: "mock")
        let db = try DatabaseManager.inMemory()
        let persistence = ChatPersistenceCoordinator(dbManager: db)
        let bootstrap = try persistence.bootstrap()

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
            persistence: persistence,
            activeConversationId: bootstrap.conversationId
        )

        container.sendDraft("Trace this request")
        try await waitForCompletion(container)

        let userMessage = try #require(container.messages.first(where: { $0.role == .user }))
        let assistantMessage = try #require(container.messages.last(where: { $0.role == .assistant }))
        let userDebugInfo = try #require(MessageDebugInfo.decode(from: userMessage.debugInfoJSON))
        let assistantDebugInfo = try #require(MessageDebugInfo.decode(from: assistantMessage.debugInfoJSON))

        #expect(userDebugInfo.requestURL == "https://example.invalid/v1/chat/completions")
        #expect(assistantDebugInfo.requestURL == "https://example.invalid/v1/chat/completions")
        #expect(userDebugInfo.responseStatusCode == 200)
        #expect(assistantDebugInfo.responseStatusCode == 200)
        #expect((userDebugInfo.traceEvents ?? []).count >= 4)
        #expect(assistantDebugInfo.providerError == nil)
    }

    private func waitForCompletion(_ container: AppContainer, timeout: Duration = .seconds(2)) async throws {
        let deadline = ContinuousClock.now + timeout
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(container.activeRequest == nil)
    }
}

private actor DebugStreamingProvider: LLMProvider {
    nonisolated let id: String

    init(id: String) {
        self.id = id
    }

    nonisolated func availableModels(context _: ProviderInvocationContext) async throws -> [ModelDescriptor] {
        await Task.yield()
        return [
            ModelDescriptor(
                id: "mock-text-1",
                displayName: "Mock Text",
                capabilities: [.text],
                modelType: .chat,
                supportedInputs: [.text],
                supportedOutputs: [.text]
            )
        ]
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ProviderResponse {
        await Task.yield()
        return ProviderResponse(text: "unused")
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
            continuation.yield(.debug(
                requestID: requestID,
                info: MessageDebugInfo(
                    requestURL: "https://example.invalid/v1/chat/completions",
                    httpMethod: "POST",
                    requestBodyJSON: #"{"model":"mock-text-1"}"#
                ).appendingTraceEvent(
                    MessageTraceEvent(
                        category: .request,
                        title: "HTTP request prepared",
                        summary: "Prepared mock chat request"
                    )
                )
            ))
            continuation.yield(.debug(
                requestID: requestID,
                info: MessageDebugInfo(
                    responseStatusCode: 200
                ).appendingTraceEvent(
                    MessageTraceEvent(
                        category: .response,
                        title: "SSE stream opened",
                        summary: "Mock stream accepted with HTTP 200"
                    )
                )
            ))
            continuation.yield(.delta(requestID: requestID, text: "Hello trace"))
            continuation.yield(.completed(requestID: requestID))
            continuation.finish()
        }
    }
}
