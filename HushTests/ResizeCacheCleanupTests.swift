import AppKit
import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
struct ResizeCacheCleanupTests {
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

    @Test("Resize debounce clears old protections and prewarms active+hot at new width")
    // swiftlint:disable:next function_body_length
    func resizeDebounceClearsProtectionsAndPrewarmsAtNewWidth() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()
        let conversationC = try coordinator.createNewConversation()

        let assistantA1 = "assistant A1 resize"
        let assistantB1 = "assistant B1 resize"
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantA1),
            conversationId: conversationA,
            status: .completed
        )
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantB1),
            conversationId: conversationB,
            status: .completed
        )

        let messagesA = try coordinator.fetchMessagePage(
            conversationId: conversationA,
            beforeOrderIndex: nil,
            limit: 20
        ).messages

        let renderCache = RenderCache(capacity: 50)
        let renderer = MessageContentRenderer(
            renderCache: renderCache,
            mathCache: MathRenderCache(capacity: 20)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let pool = HotScenePool(capacity: 2)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        // Establish baseline width before the controller has a container.
        let oldViewWidth: CGFloat = 600
        controller.view.frame = NSRect(x: 0, y: 0, width: oldViewWidth, height: 600)
        controller.viewDidLayout()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            messages: messagesA,
            sidebarThreads: [
                ConversationSidebarThread(id: conversationA, title: "A", lastActivityAt: .now),
                ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: .now),
                ConversationSidebarThread(id: conversationC, title: "C", lastActivityAt: .now)
            ],
            messageRenderRuntime: runtime
        )

        controller.update(container: container)

        // Switch to B so A becomes hot.
        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container)

        // Seed an unrelated protected key for C to verify clearAllProtections.
        let style = RenderStyle.fromTheme()
        let protectedContent = "protected-C"
        let protectedKey = RenderCache.makeKey(
            content: protectedContent,
            width: HushSpacing.chatContentMaxWidth,
            style: style
        )
        renderCache.set(
            protectedKey,
            output: MessageRenderOutput(
                attributedString: NSAttributedString(string: protectedContent),
                plainText: protectedContent,
                diagnostics: []
            )
        )
        renderCache.markProtected(key: protectedKey, conversationID: conversationC)
        #expect(renderCache.protectedKeyCountForTesting(conversationID: conversationC) == 1)

        let newViewWidth: CGFloat = 820
        let newContentWidth = CGFloat(Int(max(1, newViewWidth - HushSpacing.xl * 2)))

        let expectedA1New = MessageRenderInput(
            content: assistantA1,
            availableWidth: newContentWidth,
            style: style,
            isStreaming: false
        )
        let expectedB1New = MessageRenderInput(
            content: assistantB1,
            availableWidth: newContentWidth,
            style: style,
            isStreaming: false
        )

        // Before resize cleanup runs, new-width cache should be empty.
        #expect(renderer.cachedOutput(for: expectedA1New) == nil)
        #expect(renderer.cachedOutput(for: expectedB1New) == nil)

        // Trigger a resize; cleanup should debounce for 300ms.
        controller.view.frame = NSRect(x: 0, y: 0, width: newViewWidth, height: 600)
        controller.viewDidLayout()

        try await Task.sleep(for: .milliseconds(150))
        #expect(renderCache.protectedKeyCountForTesting(conversationID: conversationC) == 1)
        #expect(renderer.cachedOutput(for: expectedA1New) == nil)
        #expect(renderer.cachedOutput(for: expectedB1New) == nil)

        try await Task.sleep(for: .milliseconds(350))
        #expect(renderCache.protectedKeyCountForTesting(conversationID: conversationC) == 0)

        let deadline = ContinuousClock.now + .seconds(2)
        while renderer.cachedOutput(for: expectedA1New) == nil ||
            renderer.cachedOutput(for: expectedB1New) == nil,
            ContinuousClock.now < deadline
        {
            await Task.yield()
        }

        #expect(renderer.cachedOutput(for: expectedA1New) != nil)
        #expect(renderer.cachedOutput(for: expectedB1New) != nil)
    }

    @Test("Resize then immediate conversation switch does not crash and cleanup still prewarms")
    // swiftlint:disable:next function_body_length
    func resizeThenImmediateSwitchStillPrewarms() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        let assistantA1 = "assistant A1 immediate"
        let assistantB1 = "assistant B1 immediate"
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantA1),
            conversationId: conversationA,
            status: .completed
        )
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: assistantB1),
            conversationId: conversationB,
            status: .completed
        )

        let messagesA = try coordinator.fetchMessagePage(
            conversationId: conversationA,
            beforeOrderIndex: nil,
            limit: 20
        ).messages

        let renderCache = RenderCache(capacity: 50)
        let renderer = MessageContentRenderer(
            renderCache: renderCache,
            mathCache: MathRenderCache(capacity: 20)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let pool = HotScenePool(capacity: 2)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let oldViewWidth: CGFloat = 600
        controller.view.frame = NSRect(x: 0, y: 0, width: oldViewWidth, height: 600)
        controller.viewDidLayout()

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

        // Switch to B so A becomes hot.
        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container)

        let newViewWidth: CGFloat = 820
        let newContentWidth = CGFloat(Int(max(1, newViewWidth - HushSpacing.xl * 2)))

        let style = RenderStyle.fromTheme()
        let expectedA1New = MessageRenderInput(
            content: assistantA1,
            availableWidth: newContentWidth,
            style: style,
            isStreaming: false
        )
        let expectedB1New = MessageRenderInput(
            content: assistantB1,
            availableWidth: newContentWidth,
            style: style,
            isStreaming: false
        )

        controller.view.frame = NSRect(x: 0, y: 0, width: newViewWidth, height: 600)
        controller.viewDidLayout()

        // Immediate switch back while resize debounce is pending.
        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)
        controller.update(container: container)

        // After debounce, cleanup should prewarm active+hot at new width.
        let deadline = ContinuousClock.now + .seconds(2)
        while renderer.cachedOutput(for: expectedA1New) == nil ||
            renderer.cachedOutput(for: expectedB1New) == nil,
            ContinuousClock.now < deadline
        {
            await Task.yield()
        }

        #expect(renderer.cachedOutput(for: expectedA1New) != nil)
        #expect(renderer.cachedOutput(for: expectedB1New) != nil)
    }
}
