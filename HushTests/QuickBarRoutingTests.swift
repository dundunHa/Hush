import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
struct QuickBarRoutingTests {
    private func makePersistence() throws -> ChatPersistenceCoordinator {
        try ChatPersistenceCoordinator(dbManager: DatabaseManager.inMemory())
    }

    private func makeContainer(
        persistence: ChatPersistenceCoordinator? = nil
    ) throws -> AppContainer {
        var registry = ProviderRegistry()
        registry.register(InstantQuickBarProvider(id: "mock"))

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-text-1",
            parameters: .standard,
            quickBar: .standard
        )

        let activeConversationId: String
        if let persistence, let createdConversationId = try? persistence.createNewConversation() {
            activeConversationId = createdConversationId
        } else {
            activeConversationId = "conv-main"
        }

        return AppContainer.forTesting(
            settings: settings,
            registry: registry,
            persistence: persistence,
            activeConversationId: activeConversationId
        )
    }

    private func waitForQuickBarToFinish(_ container: AppContainer) async throws {
        for _ in 0 ..< 40 {
            if !container.isQuickBarSending {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Quick Bar requests stay out of the active surface but are persisted into chat history")
    func quickBarRequestsPersistIntoHistory() async throws {
        let persistence = try makePersistence()
        let container = try makeContainer(persistence: persistence)
        let activeConversationId = try #require(container.activeConversationId)

        container.toggleQuickBar()
        let didSend = container.quickBarSubmit("quick question")
        #expect(didSend)

        try await waitForQuickBarToFinish(container)

        let quickBarConversationId = try #require(container.quickBarState.conversationId)
        #expect(container.activeConversationId == activeConversationId)
        #expect(container.messages.isEmpty)
        #expect(container.sidebarThreads.first?.id == quickBarConversationId)
        #expect(container.quickBarState.messages.count == 2)
        #expect(container.quickBarState.messages.map(\.role) == [.user, .assistant])
        let persistedQuickBarMessages = try persistence.fetchMessages(conversationId: quickBarConversationId, limit: nil)
        #expect(persistedQuickBarMessages.count == 2)
        #expect(persistedQuickBarMessages.map(\.role) == [.user, .assistant])
    }

    @Test("Opening Quick Bar chat in main window activates the same persisted conversation")
    func continueQuickBarInMainChatActivatesExistingConversation() async throws {
        let persistence = try makePersistence()
        let container = try makeContainer(persistence: persistence)
        let originalConversationId = try #require(container.activeConversationId)

        container.toggleQuickBar()
        _ = container.quickBarSubmit("promote me")
        try await waitForQuickBarToFinish(container)

        let quickBarConversationId = try #require(container.quickBarState.conversationId)
        container.continueQuickBarInMainChat()

        let activatedConversationId = try #require(container.activeConversationId)
        #expect(activatedConversationId != originalConversationId)
        #expect(activatedConversationId == quickBarConversationId)
        #expect(container.messages.count == 2)
        #expect(container.sidebarThreads.first?.id == activatedConversationId)
        #expect(container.quickBarState.conversationId == activatedConversationId)
        #expect(!container.showQuickBar)

        let persistedMessages = try persistence.fetchMessages(conversationId: activatedConversationId, limit: nil)
        #expect(persistedMessages.count == 2)
        #expect(persistedMessages.map(\.role) == [.user, .assistant])
    }
}

private actor InstantQuickBarProvider: LLMProvider {
    nonisolated let id: String

    init(id: String) {
        self.id = id
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
    ) async throws -> ProviderResponse {
        ProviderResponse(text: "unused")
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
            continuation.yield(.started(requestID: requestID))
            continuation.yield(.delta(requestID: requestID, text: "Quick Bar reply"))
            continuation.yield(.completed(requestID: requestID))
            continuation.finish()
        }
    }
}
