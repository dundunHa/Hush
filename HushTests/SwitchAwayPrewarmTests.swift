import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
@Suite("Switch-away Prewarm Tests")
struct SwitchAwayPrewarmTests {
    @Test("Switch triggers prewarm for sidebar-adjacent conversation using chatContentMaxWidth")
    func switchTriggersPrewarm() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()
        let conversationC = try coordinator.createNewConversation()

        let assistantContent =
            "assistant C **markdown** " + String(repeating: "x", count: 2200)
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantContent),
            conversationId: conversationC,
            status: .completed
        )

        let sidebarThreads: [ConversationSidebarThread] = [
            ConversationSidebarThread(id: conversationA, title: "A", lastActivityAt: .now),
            ConversationSidebarThread(id: conversationC, title: "C", lastActivityAt: .now),
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
        #expect(container.activeConversationId == conversationB)

        let style = RenderStyle.fromTheme()
        let expected = MessageRenderInput(
            content: assistantContent,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: style,
            isStreaming: false
        )

        let deadline = ContinuousClock.now + .seconds(2)
        while renderer.cachedOutput(for: expected) == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(renderer.cachedOutput(for: expected) != nil)

        let wrongWidth = MessageRenderInput(
            content: assistantContent,
            availableWidth: HushSpacing.chatContentMaxWidth + 120,
            style: style,
            isStreaming: false
        )
        #expect(renderer.cachedOutput(for: wrongWidth) == nil)
    }

    @Test("Already-cached adjacent conversation is skipped")
    func cachedConversationIsSkipped() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()
        let conversationC = try coordinator.createNewConversation()

        let assistantContent = "assistant C cached"
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantContent),
            conversationId: conversationC,
            status: .completed
        )

        let sidebarThreads: [ConversationSidebarThread] = [
            ConversationSidebarThread(id: conversationA, title: "A", lastActivityAt: .now),
            ConversationSidebarThread(id: conversationC, title: "C", lastActivityAt: .now),
            ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: .now)
        ]

        let renderer = MessageContentRenderer()
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        // Pre-seed cache for the adjacent conversation's assistant content.
        let style = RenderStyle.fromTheme()
        _ = renderer.render(MessageRenderInput(
            content: assistantContent,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: style,
            isStreaming: false
        ))
        let cacheCountBefore = renderer.messageCacheCount

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

        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            await Task.yield()
        }

        #expect(renderer.messageCacheCount == cacheCountBefore)
    }
}
