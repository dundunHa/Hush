import AppKit
import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
@Suite("Hidden Scene Deferred Update Tests")
struct HiddenSceneDeferredUpdateTests {
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

    @Test("Hidden scenes do not reload on updates and apply once when becoming visible")
    func hiddenScenesDeferUpdatesUntilVisible() async throws {
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

        let pool = HotScenePool(capacity: 2)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA
        )

        controller.update(container: container)

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container)

        let sceneA = try #require(pool.sceneFor(conversationID: conversationA))
        let applyCountBefore = sceneA.applyCountForTesting
        #expect(!sceneA.needsReload)

        container.appendMessage(
            ChatMessage(role: .assistant, content: "A2"),
            toConversation: conversationA
        )

        #expect(sceneA.needsReload)
        #expect(sceneA.applyCountForTesting == applyCountBefore)

        // SwiftUI update should forward only to active scene (B), not to hidden A.
        controller.update(container: container)
        #expect(sceneA.applyCountForTesting == applyCountBefore)

        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)
        controller.update(container: container)

        let sceneAAfter = try #require(pool.sceneFor(conversationID: conversationA))
        #expect(sceneAAfter.needsReload == false)
        #expect(sceneAAfter.applyCountForTesting == applyCountBefore + 1)
    }
}
