import Foundation
@testable import Hush
import Testing

@MainActor
struct NewThreadBackgroundStreamTests {
    // MARK: - Helpers

    private func makeContainer(
        provider: some LLMProvider,
        maxConcurrent: Int = 3
    ) throws -> (AppContainer, ChatPersistenceCoordinator) {
        var registry = ProviderRegistry()
        registry.register(provider)

        let db = try DatabaseManager.inMemory()
        let persistence = ChatPersistenceCoordinator(dbManager: db)

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-text-1",
            parameters: .standard,
            quickBar: .standard,
            maxConcurrentRequests: maxConcurrent
        )

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            persistence: persistence
        )
        container.resetConversation()
        return (container, persistence)
    }

    private func waitUntilConversationFinished(
        _ container: AppContainer,
        conversationId: String,
        timeout: Duration = .seconds(8)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while container.runningConversationIds.contains(conversationId),
              ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitUntilAllIdle(
        _ container: AppContainer,
        timeout: Duration = .seconds(10)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while container.isSending, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - Core Race Condition

    @Test("New thread during streaming: first background delta marks unread dot")
    func newThreadDoesNotCancelBackgroundStream() async throws {
        // Given: provider with long delay before first delta (reproduces race window)
        let provider = DelayedStartProvider(
            id: "mock",
            preFirstDeltaDelay: .milliseconds(400),
            deltaCount: 5,
            deltaText: "bg-content "
        )
        let (container, persistence) = try makeContainer(provider: provider)

        // When: send in conv A, then immediately press "New thread"
        container.sendDraft("question for conv A")
        let convA = try #require(container.activeConversationId)

        container.resetConversation()
        let convB = try #require(container.activeConversationId)
        #expect(convA != convB)

        // When: send in conv B
        container.sendDraft("question for conv B")

        try await waitUntilConversationFinished(container, conversationId: convA)

        // Then: conv A has assistant message with content
        let bucketA = container.messagesForConversation(convA)
        let assistantInA = bucketA.last(where: { $0.role == .assistant })
        #expect(assistantInA != nil, "Conversation A must have an assistant message after background completion")
        #expect(assistantInA?.content.isEmpty == false, "Assistant message must have content")
        #expect(assistantInA?.content.contains("bg-content") == true)

        #expect(container.unreadCompletions.contains(convA), "Background conv should have unread dot after receiving deltas")

        // Then: persistence has the assistant message (restart recovery)
        let persistedMessages = try persistence.fetchMessages(conversationId: convA)
        let persistedAssistant = persistedMessages.last(where: { $0.role == .assistant })
        #expect(persistedAssistant != nil, "Assistant message must be persisted for restart recovery")
        #expect(persistedAssistant?.content.contains("bg-content") == true)

        try await waitUntilAllIdle(container)
    }

    // MARK: - Concurrency = 1 Queuing

    @Test("With maxConcurrent=1, new thread queues conv B behind running conv A")
    func concurrencyOneQueuesNewConversation() async throws {
        let provider = DelayedStartProvider(
            id: "mock",
            preFirstDeltaDelay: .milliseconds(200),
            deltaCount: 5,
            deltaText: "slow "
        )
        let (container, _) = try makeContainer(provider: provider, maxConcurrent: 1)

        // Given: conv A is streaming
        container.sendDraft("conv A message")
        let convA = try #require(container.activeConversationId)

        // When: new thread then send in conv B
        container.resetConversation()
        let convB = try #require(container.activeConversationId)
        #expect(convA != convB)

        container.sendDraft("conv B message")

        // Then: A is still running, B did not preempt A
        #expect(
            container.runningConversationIds.contains(convA),
            "Conv A should still be running (not cancelled by new thread)"
        )

        try await waitUntilAllIdle(container)

        // Then: both conversations have assistant content
        let bucketA = container.messagesForConversation(convA)
        let assistantA = bucketA.last(where: { $0.role == .assistant })
        #expect(assistantA != nil, "Conv A must have completed with an assistant message")
        #expect(assistantA?.content.isEmpty == false)

        let bucketB = container.messagesForConversation(convB)
        let assistantB = bucketB.last(where: { $0.role == .assistant })
        #expect(assistantB != nil, "Conv B must have completed after queuing")
    }
}

// MARK: - Test Provider

private actor DelayedStartProvider: LLMProvider {
    nonisolated let id: String
    let preFirstDeltaDelay: Duration
    let deltaCount: Int
    let deltaText: String

    init(
        id: String,
        preFirstDeltaDelay: Duration = .milliseconds(400),
        deltaCount: Int = 5,
        deltaText: String = "chunk "
    ) {
        self.id = id
        self.preFirstDeltaDelay = preFirstDeltaDelay
        self.deltaCount = deltaCount
        self.deltaText = deltaText
    }

    // swiftlint:disable async_without_await
    nonisolated func availableModels(
        context _: ProviderInvocationContext
    ) async throws -> [ModelDescriptor] {
        [ModelDescriptor(id: "mock-text-1", displayName: "Mock", capabilities: [.text])]
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, content: "unused")
    }

    // swiftlint:enable async_without_await

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let delay = preFirstDeltaDelay
        let count = deltaCount
        let text = deltaText
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(requestID: requestID))

                try await Task.sleep(for: delay)
                try Task.checkCancellation()

                for _ in 0 ..< count {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(10))
                    try Task.checkCancellation()
                    continuation.yield(.delta(requestID: requestID, text: text))
                }
                continuation.yield(.completed(requestID: requestID))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
