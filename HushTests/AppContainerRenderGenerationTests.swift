import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
struct AppContainerRenderGenerationTests {
    @Test("activateConversation increments activeConversationRenderGeneration when switching")
    func activateConversationIncrementsGeneration() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator
        )
        container.resetConversation()

        container.sendDraft("conversation A")
        try await waitForRequestToSettle(container)
        let conversationA = try #require(container.activeConversationId)
        let genAfterA = container.activeConversationRenderGeneration

        container.resetConversation()
        container.sendDraft("conversation B")
        try await waitForRequestToSettle(container)
        _ = try #require(container.activeConversationId)
        let genAfterB = container.activeConversationRenderGeneration

        #expect(genAfterB > genAfterA)

        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)
        let genAfterSwitchBackToA = container.activeConversationRenderGeneration

        #expect(genAfterSwitchBackToA > genAfterB)
        #expect(container.activeConversationId == conversationA)
    }

    @Test("retryActiveConversationLoad increments activeConversationRenderGeneration")
    func retryActiveConversationLoadIncrementsGeneration() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator
        )
        container.resetConversation()

        container.sendDraft("test message")
        try await waitForRequestToSettle(container)
        let conversationId = try #require(container.activeConversationId)

        let genBefore = container.activeConversationRenderGeneration

        container.retryActiveConversationLoad()
        try await waitForConversationReady(container, conversationId: conversationId)
        let genAfterRetry = container.activeConversationRenderGeneration

        #expect(genAfterRetry > genBefore)
        #expect(container.activeConversationId == conversationId)
    }

    @Test("Generation increment ensures stale rendering is dropped by ConversationRenderScheduler")
    func generationIncrementPreventsStaleRendering() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator
        )
        container.resetConversation()

        container.sendDraft("conversation A")
        try await waitForRequestToSettle(container)
        let conversationA = try #require(container.activeConversationId)
        let genAfterA = container.activeConversationRenderGeneration

        container.resetConversation()
        container.sendDraft("conversation B")
        try await waitForRequestToSettle(container)
        let genAfterB = container.activeConversationRenderGeneration

        #expect(genAfterB > genAfterA)

        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)
        let genAfterSwitchBackToA = container.activeConversationRenderGeneration

        #expect(genAfterSwitchBackToA > genAfterB)
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
}
