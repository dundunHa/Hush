import AppKit
import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
@Suite("Hot Scene Pool Tests")
struct HotScenePoolTests {
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

    @Test("Pool evicts empty scenes before non-empty scenes")
    func poolEvictsEmptyBeforeNonEmpty() {
        let pool = HotScenePool(capacity: 3)
        let container = AppContainer.forTesting(settings: .testDefault)

        _ = pool.switchTo(conversationID: "A", messageCount: 0, generation: 1) {
            ConversationViewController(container: container)
        }
        _ = pool.switchTo(conversationID: "B", messageCount: 0, generation: 1) {
            ConversationViewController(container: container)
        }
        _ = pool.switchTo(conversationID: "C", messageCount: 5, generation: 1) {
            ConversationViewController(container: container)
        }

        // Touch B so A becomes the LRU empty scene.
        _ = pool.switchTo(conversationID: "B", messageCount: 0, generation: 1) {
            ConversationViewController(container: container)
        }

        let result = pool.switchTo(conversationID: "D", messageCount: 5, generation: 1) {
            ConversationViewController(container: container)
        }

        #expect(result.evicted?.conversationID == "A")
        #expect(pool.sceneFor(conversationID: "A") == nil)
    }

    @Test("Pool evicts least-recently-used when no empty scenes exist")
    func poolEvictsLRUWhenNoEmpty() {
        let pool = HotScenePool(capacity: 3)
        let container = AppContainer.forTesting(settings: .testDefault)

        _ = pool.switchTo(conversationID: "A", messageCount: 1, generation: 1) {
            ConversationViewController(container: container)
        }
        _ = pool.switchTo(conversationID: "B", messageCount: 1, generation: 1) {
            ConversationViewController(container: container)
        }
        _ = pool.switchTo(conversationID: "C", messageCount: 1, generation: 1) {
            ConversationViewController(container: container)
        }

        // Touch B so A becomes LRU.
        _ = pool.switchTo(conversationID: "B", messageCount: 1, generation: 1) {
            ConversationViewController(container: container)
        }

        let result = pool.switchTo(conversationID: "D", messageCount: 1, generation: 1) {
            ConversationViewController(container: container)
        }

        #expect(result.evicted?.conversationID == "A")
        #expect(pool.sceneFor(conversationID: "A") == nil)
    }

    @Test("hotConversationIDs excludes active conversation")
    func hotConversationIDsExcludesActive() {
        let pool = HotScenePool(capacity: 3)
        let container = AppContainer.forTesting(settings: .testDefault)

        _ = pool.switchTo(conversationID: "A", messageCount: 1, generation: 1) {
            ConversationViewController(container: container)
        }
        _ = pool.switchTo(conversationID: "B", messageCount: 1, generation: 1) {
            ConversationViewController(container: container)
        }
        _ = pool.switchTo(conversationID: "C", messageCount: 1, generation: 1) {
            ConversationViewController(container: container)
        }

        #expect(pool.hotConversationIDs == ["A", "B"])
    }

    @Test("Controller reuses hot scene without reloading when not dirty")
    func controllerReusesSceneWithoutReload() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: "A1"),
            conversationId: conversationA,
            status: .completed
        )
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: "B1"),
            conversationId: conversationB,
            status: .completed
        )

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let pool = HotScenePool(capacity: 3)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            sidebarThreads: []
        )

        controller.update(container: container)
        let sceneA = try #require(pool.sceneFor(conversationID: conversationA))
        let applyCountAfterFirst = sceneA.applyCountForTesting
        #expect(applyCountAfterFirst > 0)

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container)

        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)
        controller.update(container: container)

        let sceneAAfter = try #require(pool.sceneFor(conversationID: conversationA))
        #expect(sceneAAfter.applyCountForTesting == applyCountAfterFirst)
        #expect(sceneAAfter.view.isHidden == false)
    }

    @Test("Evicted scenes are removed from view hierarchy")
    func evictionCleansUpHierarchy() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let c1 = try coordinator.createNewConversation()
        let c2 = try coordinator.createNewConversation()
        let c3 = try coordinator.createNewConversation()
        let c4 = try coordinator.createNewConversation()

        // Make c2/c3/c4 non-empty; c1 stays empty to be evicted first.
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: "c2"),
            conversationId: c2,
            status: .completed
        )
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: "c3"),
            conversationId: c3,
            status: .completed
        )
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: "c4"),
            conversationId: c4,
            status: .completed
        )

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let pool = HotScenePool(capacity: 3)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: c1,
            sidebarThreads: []
        )

        controller.update(container: container)
        try await waitForConversationReady(container, conversationId: c1)

        container.activateConversation(conversationId: c2)
        try await waitForConversationReady(container, conversationId: c2)
        controller.update(container: container)

        container.activateConversation(conversationId: c3)
        try await waitForConversationReady(container, conversationId: c3)
        controller.update(container: container)

        let sceneC1 = try #require(pool.sceneFor(conversationID: c1))

        container.activateConversation(conversationId: c4)
        try await waitForConversationReady(container, conversationId: c4)
        controller.update(container: container)

        #expect(pool.sceneFor(conversationID: c1) == nil)
        #expect(sceneC1.parent == nil)
        #expect(sceneC1.view.superview == nil)
    }

    @Test("Hot scene pool capacity remains within hard bound")
    func hotScenePoolCapacityBound() {
        #expect(RenderConstants.hotScenePoolCapacity > 0)
        #expect(RenderConstants.hotScenePoolCapacity <= 6)
    }
}
