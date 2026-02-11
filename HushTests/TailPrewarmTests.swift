import AppKit
import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
@Suite("Tail Prewarm Tests")
struct TailPrewarmTests {
    private func waitForConversationReady(
        _ container: AppContainer,
        conversationId: String,
        timeout: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if container.activeConversationId == conversationId,
               container.statusMessage == "Ready"
            {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitForStreamingStart(
        _ container: AppContainer,
        conversationId: String,
        timeout: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if container.runningConversationIds.contains(conversationId) {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitForStreamingComplete(
        _ container: AppContainer,
        conversationId: String,
        timeout: Duration = .seconds(3)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !container.runningConversationIds.contains(conversationId) {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Hot scene streaming completion triggers tail prewarm for latest assistant messages")
    func hotSceneStreamingCompleteTriggersTailPrewarm() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        let assistantA1 = "assistant A1 old"
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantA1),
            conversationId: conversationA,
            status: .completed
        )

        let messagesA = try coordinator.fetchMessagePage(
            conversationId: conversationA,
            beforeOrderIndex: nil,
            limit: 20
        ).messages

        let renderer = MessageContentRenderer()
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        var registry = ProviderRegistry()
        registry.register(
            MockProvider(
                id: "mock",
                streamBehavior: MockStreamBehavior(
                    chunks: ["A2", "-", "done"],
                    delayPerChunk: .milliseconds(40)
                )
            )
        )

        let pool = HotScenePool(capacity: 2)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            messages: messagesA,
            sidebarThreads: [
                ConversationSidebarThread(id: conversationA, title: "A", lastActivityAt: .now),
                ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: .now)
            ],
            messageRenderRuntime: runtime
        )

        controller.update(container: container)

        container.sendDraft("start streaming")
        try await waitForStreamingStart(container, conversationId: conversationA)

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container)

        try await waitForStreamingComplete(container, conversationId: conversationA)

        let style = RenderStyle.fromTheme()
        let expectedA1 = MessageRenderInput(
            content: assistantA1,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: style,
            isStreaming: false
        )

        let deadline = ContinuousClock.now + .seconds(2)
        while renderer.cachedOutput(for: expectedA1) == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }

        #expect(renderer.cachedOutput(for: expectedA1) != nil)
    }

    @Test("Tail prewarm only renders missing cache entries")
    func tailPrewarmSkipsAlreadyCachedMessages() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        let assistantA1 = "assistant A1 cached"
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantA1),
            conversationId: conversationA,
            status: .completed
        )

        let messagesA = try coordinator.fetchMessagePage(
            conversationId: conversationA,
            beforeOrderIndex: nil,
            limit: 20
        ).messages

        let renderer = MessageContentRenderer()
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let style = RenderStyle.fromTheme()
        _ = renderer.render(MessageRenderInput(
            content: assistantA1,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: style,
            isStreaming: false
        ))
        let renderCountBefore = renderer.nonStreamingMissRenderCountForTesting

        let streamedAssistant = "A2-streamed-final"

        var registry = ProviderRegistry()
        registry.register(
            MockProvider(
                id: "mock",
                streamBehavior: MockStreamBehavior(
                    chunks: [streamedAssistant],
                    delayPerChunk: .milliseconds(30)
                )
            )
        )

        let pool = HotScenePool(capacity: 2)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            messages: messagesA,
            sidebarThreads: [
                ConversationSidebarThread(id: conversationA, title: "A", lastActivityAt: .now),
                ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: .now)
            ],
            messageRenderRuntime: runtime
        )

        controller.update(container: container)

        container.sendDraft("start streaming")
        try await waitForStreamingStart(container, conversationId: conversationA)

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container)

        try await waitForStreamingComplete(container, conversationId: conversationA)

        let expectedA2 = MessageRenderInput(
            content: streamedAssistant,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: style,
            isStreaming: false
        )
        let deadline = ContinuousClock.now + .seconds(2)
        while renderer.cachedOutput(for: expectedA2) == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }

        #expect(renderer.cachedOutput(for: expectedA2) != nil)
        #expect(renderer.nonStreamingMissRenderCountForTesting == renderCountBefore + 1)
    }

    @Test("Cold conversation streaming completion uses one-shot final-message prewarm (no tail prewarm)")
    func coldConversationUsesOneShotFinalMessagePrewarm() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        let assistantA1 = "assistant A1 should stay uncached"
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantA1),
            conversationId: conversationA,
            status: .completed
        )

        let messagesA = try coordinator.fetchMessagePage(
            conversationId: conversationA,
            beforeOrderIndex: nil,
            limit: 20
        ).messages

        let renderer = MessageContentRenderer()
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let streamedAssistant = "A2-final"

        var registry = ProviderRegistry()
        registry.register(
            MockProvider(
                id: "mock",
                streamBehavior: MockStreamBehavior(
                    chunks: [streamedAssistant],
                    delayPerChunk: .milliseconds(30)
                )
            )
        )

        // Capacity 1 ensures switching evicts A's scene, making it cold.
        let pool = HotScenePool(capacity: 1)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            messages: messagesA,
            sidebarThreads: [
                ConversationSidebarThread(id: conversationA, title: "A", lastActivityAt: .now),
                ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: .now)
            ],
            messageRenderRuntime: runtime
        )

        controller.update(container: container)

        container.sendDraft("start streaming")
        try await waitForStreamingStart(container, conversationId: conversationA)

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container)

        try await waitForStreamingComplete(container, conversationId: conversationA)

        let style = RenderStyle.fromTheme()
        let expectedA2 = MessageRenderInput(
            content: streamedAssistant,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: style,
            isStreaming: false
        )

        let deadline = ContinuousClock.now + .seconds(2)
        while renderer.cachedOutput(for: expectedA2) == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }

        #expect(renderer.cachedOutput(for: expectedA2) != nil)

        let expectedA1 = MessageRenderInput(
            content: assistantA1,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: style,
            isStreaming: false
        )
        #expect(renderer.cachedOutput(for: expectedA1) == nil)
    }
}
