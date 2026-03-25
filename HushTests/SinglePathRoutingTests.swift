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

    @Test("Preloaded quick bar state is not overwritten when the view loads")
    func preloadedQuickBarStateSurvivesLoadView() {
        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let activeConversationID = "conv-main"
        let quickBarConversationID = "conv-quickbar"
        let activeMessages = [
            ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "Hi! How can I help you today?",
                createdAt: Date(timeIntervalSince1970: 1_700_000_400)
            )
        ]
        let quickBarMessages = [
            ChatMessage(
                id: UUID(),
                role: .user,
                content: "Summarize this PR",
                createdAt: Date(timeIntervalSince1970: 1_700_000_401)
            ),
            ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "Quick Bar reply.",
                createdAt: Date(timeIntervalSince1970: 1_700_000_402)
            )
        ]

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            activeConversationId: activeConversationID,
            messages: activeMessages
        )

        let controller = ConversationViewController(
            container: container,
            theme: container.settings.theme,
            surfaceStyle: .quickBar,
            bottomReservedHeight: 0
        )

        controller.applyConversationState(
            conversationId: quickBarConversationID,
            messages: quickBarMessages,
            isSending: false,
            generation: 1,
            container: container
        )

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.messageTableViewForTesting.prepareCellForTesting(row: 0)
        controller.messageTableViewForTesting.prepareCellForTesting(row: 1)

        #expect(controller.applyCountForTesting == 1)
        #expect(controller.messageTableViewForTesting.tableView.numberOfRows == 2)
        #expect(controller.messageTableViewForTesting.visibleCellForTesting(row: 0)?.attributedStringForTesting.string == "Summarize this PR")
        #expect(controller.messageTableViewForTesting.visibleCellForTesting(row: 1)?.attributedStringForTesting.string == "Quick Bar reply.")
    }
}
