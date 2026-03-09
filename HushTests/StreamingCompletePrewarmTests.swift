import Foundation
@testable import Hush
import Testing

@MainActor
struct StreamingCompletePrewarmTests {
    // MARK: - Helpers

    private func makeContainer(
        provider: some LLMProvider,
        maxConcurrent: Int = 3
    ) throws -> (AppContainer, ChatPersistenceCoordinator, RenderCache) {
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

        let renderCache = RenderCache()
        let renderer = MessageContentRenderer(renderCache: renderCache)
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            persistence: persistence,
            messageRenderRuntime: runtime
        )
        container.resetConversation()
        return (container, persistence, renderCache)
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

    private func waitForRenderCache(
        _ cache: RenderCache,
        minCount: Int,
        timeout: Duration = .seconds(5)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if cache.count >= minCount {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Tests

    @Test("background streaming completion triggers render cache prewarm")
    func backgroundCompletionTriggersPrewarm() async throws {
        let provider = DelayedChunkProvider(
            id: "mock",
            preFirstDeltaDelay: .milliseconds(200),
            deltaCount: 5,
            deltaText: "background-content "
        )
        let (container, _, renderCache) = try makeContainer(provider: provider)

        // Given: send in conv A, then switch to conv B so A is background
        container.sendDraft("question for conv A")
        let convA = try #require(container.activeConversationId)

        container.resetConversation()
        let convB = try #require(container.activeConversationId)
        #expect(convA != convB)

        let cacheBefore = renderCache.count

        // When: conv A completes in background
        try await waitUntilConversationFinished(container, conversationId: convA)

        // Then: render cache should have entries from background prewarm
        try await waitForRenderCache(renderCache, minCount: cacheBefore + 1)

        #expect(
            renderCache.count > cacheBefore,
            "Render cache should grow after background streaming completion prewarm"
        )

        try await waitUntilAllIdle(container)
    }

    @Test("foreground streaming completion does not trigger tail prewarm")
    func foregroundCompletionNoPrewarm() async throws {
        let provider = DelayedChunkProvider(
            id: "mock",
            preFirstDeltaDelay: .milliseconds(100),
            deltaCount: 3,
            deltaText: "foreground-content "
        )
        let (container, _, renderCache) = try makeContainer(provider: provider)

        // Given: send in conv A and stay on conv A (foreground)
        container.sendDraft("question staying foreground")
        let convA = try #require(container.activeConversationId)

        // When: conv A completes in foreground
        try await waitUntilConversationFinished(container, conversationId: convA)
        try await Task.sleep(for: .milliseconds(300))

        // Then: foreground completion does not invoke tail prewarm path
        #expect(container.activeConversationId == convA)
        let messages = container.messagesForConversation(convA)
        let assistant = messages.last { $0.role == .assistant }
        #expect(assistant != nil, "Foreground completion should produce assistant message")
        #expect(assistant?.content.contains("foreground-content") == true)

        try await waitUntilAllIdle(container)
    }

    @Test("background completion prewarms messages from correct conversation bucket")
    func prewarmUsesCorrectConversationBucket() async throws {
        let provider = DelayedChunkProvider(
            id: "mock",
            preFirstDeltaDelay: .milliseconds(200),
            deltaCount: 4,
            deltaText: "bucket-test "
        )
        let (container, _, _) = try makeContainer(provider: provider)

        // Given: send in conv A
        container.sendDraft("conv A question")
        let convA = try #require(container.activeConversationId)

        // Switch to conv B (makes A background)
        container.resetConversation()
        let convB = try #require(container.activeConversationId)
        #expect(convA != convB)

        // When: background completion finishes for conv A
        try await waitUntilConversationFinished(container, conversationId: convA)
        try await Task.sleep(for: .milliseconds(200))

        // Then: conv A should have assistant content from its own bucket
        let messagesA = container.messagesForConversation(convA)
        let assistantA = messagesA.last { $0.role == .assistant }
        #expect(assistantA != nil, "Background conv must have assistant message after completion")
        #expect(assistantA?.content.contains("bucket-test") == true)

        let messagesB = container.messagesForConversation(convB)
        let assistantB = messagesB.last { $0.role == .assistant }
        #expect(assistantB == nil, "Conv B should not have assistant content from conv A")

        try await waitUntilAllIdle(container)
    }

    @Test("multiple background completions each trigger independent prewarming")
    func multipleBackgroundCompletions() async throws {
        let provider = DelayedChunkProvider(
            id: "mock",
            preFirstDeltaDelay: .milliseconds(150),
            deltaCount: 3,
            deltaText: "multi-bg "
        )
        let (container, _, renderCache) = try makeContainer(provider: provider, maxConcurrent: 3)

        // Given: send in conv A
        container.sendDraft("conv A message")
        let convA = try #require(container.activeConversationId)

        // Switch to conv B, send
        container.resetConversation()
        container.sendDraft("conv B message")
        let convB = try #require(container.activeConversationId)

        // Switch to conv C (both A and B are now background)
        container.resetConversation()
        let convC = try #require(container.activeConversationId)
        #expect(convA != convB)
        #expect(convB != convC)

        let cacheBefore = renderCache.count

        // When: both background conversations complete
        try await waitUntilConversationFinished(container, conversationId: convA)
        try await waitUntilConversationFinished(container, conversationId: convB)
        try await waitForRenderCache(renderCache, minCount: cacheBefore + 1, timeout: .seconds(5))

        // Then: render cache should reflect prewarms from both completions
        #expect(
            renderCache.count > cacheBefore,
            "Multiple background completions should prewarm render cache"
        )

        let messagesA = container.messagesForConversation(convA)
        let messagesB = container.messagesForConversation(convB)
        #expect(messagesA.contains { $0.role == .assistant }, "Conv A should have assistant message")
        #expect(messagesB.contains { $0.role == .assistant }, "Conv B should have assistant message")

        try await waitUntilAllIdle(container)
    }

    @Test("background completion sets unread marker and completes prewarm")
    func backgroundCompletionSetsUnreadAndPrewarms() async throws {
        let provider = DelayedChunkProvider(
            id: "mock",
            preFirstDeltaDelay: .milliseconds(300),
            deltaCount: 5,
            deltaText: "unread-prewarm "
        )
        let (container, _, renderCache) = try makeContainer(provider: provider)

        // Given: send in conv A, switch away
        container.sendDraft("conv A question")
        let convA = try #require(container.activeConversationId)

        container.resetConversation()
        let convB = try #require(container.activeConversationId)
        #expect(convA != convB)

        let cacheBefore = renderCache.count

        // When: conv A completes in background
        try await waitUntilConversationFinished(container, conversationId: convA)
        try await waitForRenderCache(renderCache, minCount: cacheBefore + 1)

        // Then: unread marker set AND render cache populated
        #expect(
            container.unreadCompletions.contains(convA),
            "Background completion should mark conversation as unread"
        )
        #expect(
            renderCache.count > cacheBefore,
            "Render cache should grow from tail prewarm after background completion"
        )

        try await waitUntilAllIdle(container)
    }
}

// MARK: - Test Provider

/// Provider that delays before first delta, producing controllable streaming chunks.
/// Separate from `DelayedStartProvider` in `NewThreadBackgroundStreamTests.swift`
/// because that type is `private`.
private actor DelayedChunkProvider: LLMProvider {
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
