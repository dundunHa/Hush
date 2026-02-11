import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
@Suite("AppContainer Streaming Fast-Track")
struct AppContainerStreamingFastTrackTests {
    @Test("pushStreamingContent routes to active scene only and no-ops without scene")
    func pushStreamingContentRoutesToActiveSceneOnly() throws {
        let container = AppContainer.forTesting(
            settings: .testDefault,
            activeConversationId: "conv-a"
        )
        let pool = HotScenePool(capacity: 2)
        container.registerHotScenePool(pool)

        let sceneA = ConversationViewController(container: container)
        _ = pool.switchTo(conversationID: "conv-a", messageCount: 0, generation: 1) {
            sceneA
        }

        try container.pushStreamingContent(
            conversationId: "conv-b",
            messageID: #require(UUID(uuidString: "77777777-AAAA-BBBB-CCCC-777777777777")),
            content: "ignored"
        )
        #expect(sceneA.streamingPushCountForTesting == 0)

        try container.pushStreamingContent(
            conversationId: "conv-a",
            messageID: #require(UUID(uuidString: "88888888-AAAA-BBBB-CCCC-888888888888")),
            content: "delivered"
        )
        #expect(sceneA.streamingPushCountForTesting == 1)
        #expect(sceneA.lastStreamingPushContentForTesting == "delivered")

        let noSceneContainer = AppContainer.forTesting(
            settings: .testDefault,
            activeConversationId: "conv-a"
        )
        try noSceneContainer.pushStreamingContent(
            conversationId: "conv-a",
            messageID: #require(UUID(uuidString: "99999999-AAAA-BBBB-CCCC-999999999999")),
            content: "no-scene"
        )
    }

    @Test("Switching back to a streaming conversation triggers immediate content push")
    func switchBackToStreamingConversationPushesImmediately() async throws {
        let db = try DatabaseManager.inMemory()
        let persistence = ChatPersistenceCoordinator(dbManager: db)

        var registry = ProviderRegistry()
        registry.register(SwitchBackStreamingProvider())

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
            persistence: persistence
        )
        container.resetConversation()
        let conversationA = try #require(container.activeConversationId)

        let pool = HotScenePool(capacity: 2)
        container.registerHotScenePool(pool)
        let sceneA = ConversationViewController(container: container)
        _ = pool.switchTo(conversationID: conversationA, messageCount: 0, generation: 1) {
            sceneA
        }

        container.sendDraft("start")
        try await waitForFirstAssistantMessage(container)

        // Before chunk #2 arrives, switch away and back.
        let beforeSwitchBack = sceneA.streamingPushCountForTesting
        container.resetConversation()
        try await Task.sleep(for: .milliseconds(40))
        container.activateConversation(conversationId: conversationA)
        try await Task.sleep(for: .milliseconds(40))

        #expect(sceneA.streamingPushCountForTesting > beforeSwitchBack)
        #expect(sceneA.lastStreamingPushContentForTesting == "A")

        // Cleanup running stream for test isolation.
        container.stopActiveRequest()
    }

    private func waitForFirstAssistantMessage(
        _ container: AppContainer,
        timeout: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let assistant = container.messages.last(where: { $0.role == .assistant }),
               assistant.content == "A"
            {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private actor SwitchBackStreamingProvider: LLMProvider {
    nonisolated let id: String = "mock"

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
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(requestID: requestID))
                continuation.yield(.delta(requestID: requestID, text: "A"))
                try await Task.sleep(for: .milliseconds(300))
                continuation.yield(.delta(requestID: requestID, text: "B"))
                try await Task.sleep(for: .milliseconds(300))
                continuation.yield(.delta(requestID: requestID, text: "C"))
                continuation.yield(.completed(requestID: requestID))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
