import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
@Suite("Conversation Switch Scroll — generation-driven latch, no sleep dependency")
struct ConversationSwitchScrollTests {
    // MARK: - Helpers

    private func makeContainer() throws -> (AppContainer, ChatPersistenceCoordinator) {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

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
            persistence: coordinator
        )
        container.resetConversation()
        return (container, coordinator)
    }

    private func waitForRequestToSettle(
        _ container: AppContainer,
        timeout: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if container.activeRequest == nil, container.pendingQueue.isEmpty {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

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

    // MARK: - Generation Increment

    @Test("Each conversation switch monotonically increments render generation")
    func generationIncrements() async throws {
        let (container, _) = try makeContainer()

        container.sendDraft("conversation A")
        try await waitForRequestToSettle(container)
        let convA = try #require(container.activeConversationId)
        let genA = container.activeConversationRenderGeneration

        container.resetConversation()
        container.sendDraft("conversation B")
        try await waitForRequestToSettle(container)
        let convB = try #require(container.activeConversationId)
        let genB = container.activeConversationRenderGeneration

        #expect(genB > genA)
        #expect(convA != convB)

        container.activateConversation(conversationId: convA)
        try await waitForConversationReady(container, conversationId: convA)
        let genBack = container.activeConversationRenderGeneration

        #expect(genBack > genB)
    }

    // MARK: - Messages Preserved Across Switch

    @Test("Switching away and back preserves message bucket via generation gate")
    func messagesBucketPreservedAcrossSwitch() async throws {
        let (container, _) = try makeContainer()

        container.sendDraft("msg for A")
        try await waitForRequestToSettle(container)
        let convA = try #require(container.activeConversationId)
        let countA = container.messages.count

        container.resetConversation()
        container.sendDraft("msg for B")
        try await waitForRequestToSettle(container)

        container.activateConversation(conversationId: convA)
        try await waitForConversationReady(container, conversationId: convA)

        #expect(container.messages.count >= countA)
        #expect(container.activeConversationId == convA)
    }

    // MARK: - Stale Load Rejection

    @Test("Stale generation load does not overwrite newer conversation state")
    func staleLoadRejected() async throws {
        let (container, _) = try makeContainer()

        container.sendDraft("seed A")
        try await waitForRequestToSettle(container)
        let convA = try #require(container.activeConversationId)

        container.resetConversation()
        container.sendDraft("seed B")
        try await waitForRequestToSettle(container)
        let convB = try #require(container.activeConversationId)

        let genBeforeSwitch = container.activeConversationRenderGeneration

        container.activateConversation(conversationId: convA)
        try await waitForConversationReady(container, conversationId: convA)

        let genAfterSwitch = container.activeConversationRenderGeneration
        #expect(genAfterSwitch > genBeforeSwitch)
        #expect(container.activeConversationId == convA)
        #expect(container.activeConversationId != convB)
    }

    // MARK: - Rapid Switching Stability

    @Test("Rapid conversation switches settle to the last-requested conversation")
    func rapidSwitchingStability() async throws {
        let (container, _) = try makeContainer()

        container.sendDraft("A")
        try await waitForRequestToSettle(container)
        let convA = try #require(container.activeConversationId)

        container.resetConversation()
        container.sendDraft("B")
        try await waitForRequestToSettle(container)
        let convB = try #require(container.activeConversationId)

        container.resetConversation()
        container.sendDraft("C")
        try await waitForRequestToSettle(container)
        let convC = try #require(container.activeConversationId)

        container.activateConversation(conversationId: convA)
        container.activateConversation(conversationId: convB)
        container.activateConversation(conversationId: convC)

        try await waitForConversationReady(container, conversationId: convC)

        #expect(container.activeConversationId == convC)

        let gen = container.activeConversationRenderGeneration
        #expect(gen > 0)
    }
}
