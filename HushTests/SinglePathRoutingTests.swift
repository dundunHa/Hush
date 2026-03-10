import AppKit
import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
struct SinglePathRoutingTests {
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

    @Test("ConversationViewController applies conversation updates on switch")
    func appliesConversationUpdatesOnSwitch() async throws {
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

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA
        )

        let controller = ConversationViewController(container: container, theme: container.settings.theme)
        controller.loadViewIfNeeded()

        let initialApplyCount = controller.applyCountForTesting
        #expect(initialApplyCount > 0)

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container, theme: container.settings.theme)

        #expect(controller.applyCountForTesting == initialApplyCount + 1)
    }
}
