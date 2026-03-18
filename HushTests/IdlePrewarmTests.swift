import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
@Suite(.serialized)
struct IdlePrewarmTests {
    private struct ConversationReadyTimeoutError: Error {}

    private func waitForConversationReady(
        _ container: AppContainer,
        conversationId: String,
        timeout: Duration = .seconds(10)
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

        throw ConversationReadyTimeoutError()
    }

    @Test("Idle timeout triggers prewarm for hot conversations")
    func idleTimeoutTriggersPrewarm() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        let assistantContent = "assistant B **idle**"
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantContent),
            conversationId: conversationB,
            status: .completed
        )

        let sidebarThreads: [ConversationSidebarThread] = [
            ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: .now)
        ]

        let renderer = MessageContentRenderer()
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            messages: [],
            sidebarThreads: sidebarThreads,
            messageRenderRuntime: runtime
        )

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)

        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)

        let style = RenderStyle.fromTheme()
        let expected = MessageRenderInput(
            content: assistantContent,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: style,
            isStreaming: false
        )

        let deadline = ContinuousClock.now + .seconds(12)
        while renderer.cachedOutput(for: expected) == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(renderer.cachedOutput(for: expected) != nil)
    }

    @Test("User activity cancels in-progress idle prewarm and retains completed entries")
    func userActivityCancelsInProgressPrewarm() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        for index in 0 ..< RenderConstants.startupRenderPrewarmAssistantMessageCap {
            let content =
                "assistant B \(index)\n" +
                String(repeating: "math $x_{\(index)}$ ", count: 200) +
                "\n" +
                String(repeating: "y", count: 2000)
            try coordinator.persistSystemMessage(
                ChatMessage(role: .assistant, content: content),
                conversationId: conversationB,
                status: .completed
            )
        }

        let sidebarThreads: [ConversationSidebarThread] = [
            ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: .now)
        ]

        let renderer = MessageContentRenderer()
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            messages: [],
            sidebarThreads: sidebarThreads,
            messageRenderRuntime: runtime
        )

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)

        // Wait for idle prewarm to start (first cache entry appears), then cancel via typing.
        let startDeadline = ContinuousClock.now + .seconds(6)
        while renderer.messageCacheCount == 0, ContinuousClock.now < startDeadline {
            await Task.yield()
        }
        #expect(renderer.messageCacheCount > 0)

        container.sendDraft("typing cancels idle prewarm")
        await Task.yield()

        let countAfterCancel = renderer.messageCacheCount
        #expect(countAfterCancel > 0)
        #expect(countAfterCancel < RenderConstants.startupRenderPrewarmAssistantMessageCap)
    }

    @Test("Idle prewarm only renders missing cache entries")
    func idlePrewarmSkipsAlreadyCachedInputs() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        let assistantContent = "assistant B cached already"
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantContent),
            conversationId: conversationB,
            status: .completed
        )

        let sidebarThreads: [ConversationSidebarThread] = [
            ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: .now)
        ]

        let renderer = MessageContentRenderer()
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            messages: [],
            sidebarThreads: sidebarThreads,
            messageRenderRuntime: runtime
        )

        let style = RenderStyle.fromTheme()
        _ = renderer.render(MessageRenderInput(
            content: assistantContent,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: style,
            isStreaming: false
        ))
        let cacheCountBefore = renderer.messageCacheCount

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)

        // Allow idle prewarm window to elapse; it should not add entries for already-cached content.
        try await Task.sleep(for: .seconds(6))
        #expect(renderer.messageCacheCount == cacheCountBefore)
    }

    @Test("Idle prewarm yields between messages so other main-actor work can run")
    func idlePrewarmYieldsBetweenMessages() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        for index in 0 ..< RenderConstants.startupRenderPrewarmAssistantMessageCap {
            let content =
                "assistant B yield \(index)\n" +
                String(repeating: "table | row |\n", count: 200) +
                String(repeating: "z", count: 2000)
            try coordinator.persistSystemMessage(
                ChatMessage(role: .assistant, content: content),
                conversationId: conversationB,
                status: .completed
            )
        }

        let sidebarThreads: [ConversationSidebarThread] = [
            ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: .now)
        ]

        let renderer = MessageContentRenderer()
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            messages: [],
            sidebarThreads: sidebarThreads,
            messageRenderRuntime: runtime
        )

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)

        let startDeadline = ContinuousClock.now + .seconds(6)
        while renderer.messageCacheCount == 0, ContinuousClock.now < startDeadline {
            await Task.yield()
        }
        #expect(renderer.messageCacheCount > 0)

        var capturedCacheCountAtOtherWork: Int?
        Task {
            capturedCacheCountAtOtherWork = renderer.messageCacheCount
        }

        let otherDeadline = ContinuousClock.now + .seconds(1)
        while capturedCacheCountAtOtherWork == nil, ContinuousClock.now < otherDeadline {
            await Task.yield()
        }

        let captured = try #require(capturedCacheCountAtOtherWork)
        #expect(captured < RenderConstants.startupRenderPrewarmAssistantMessageCap)
    }
}
