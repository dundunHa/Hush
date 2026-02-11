import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
@Suite("AppContainer Persistence Semantics Tests")
struct AppContainerPersistenceSemanticsTests {
    @Test("Queue-full rejection produces zero durable writes for rejected submission")
    func queueFullRejectionZeroDurableWrites() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        var registry = ProviderRegistry()
        registry.register(
            MockProvider(
                id: "mock",
                streamBehavior: MockStreamBehavior(
                    chunks: ["slow"],
                    delayPerChunk: .seconds(5)
                )
            )
        )

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator
        )
        container.resetConversation()

        let expectedAccepted = RuntimeConstants.pendingQueueCapacity + 1
        let rejectedPrompt = "msg-\(expectedAccepted)"
        for index in 0 ..< (expectedAccepted + 1) {
            container.sendDraft("msg-\(index)")
        }

        #expect(container.statusMessage.contains("Queue full"))

        let persistedUserCount = try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM messages WHERE role = ?",
                arguments: ["user"]
            ) ?? 0
        }
        #expect(persistedUserCount == expectedAccepted)

        let persistedRejectedPromptCount = try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM messages WHERE role = ? AND content = ?",
                arguments: ["user", rejectedPrompt]
            ) ?? 0
        }
        #expect(persistedRejectedPromptCount == 0)

        let messageOutboxInsertCount = try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM syncOutbox WHERE entityType = ? AND operationType = ?",
                arguments: ["message", OutboxOperationType.insert.rawValue]
            ) ?? 0
        }
        #expect(messageOutboxInsertCount == expectedAccepted)

        container.stopActiveRequest()
    }

    @Test("Late events after terminal do not mutate durable assistant record")
    func lateEventsAfterTerminalIgnored() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        var registry = ProviderRegistry()
        registry.register(LateEventProvider())

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator
        )
        container.resetConversation()

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(container.activeRequest == nil)

        let persistedAssistant = try db.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT content, status
                FROM messages
                WHERE role = ?
                ORDER BY orderIndex DESC
                LIMIT 1
                """,
                arguments: ["assistant"]
            )
        }

        #expect(persistedAssistant?["content"] as String? == "A")
        #expect(persistedAssistant?["status"] as String? == MessageStatus.completed.rawValue)
        #expect(container.messages.last(where: { $0.role == .assistant })?.content == "A")
    }

    @Test("Reset conversation keeps sidebar history entries")
    func resetConversationKeepsSidebarHistory() throws {
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

        container.sendDraft("persist in sidebar")
        #expect(container.sidebarThreads.count == 1)
        #expect(container.sidebarThreads.first?.title == "persist in sidebar")

        container.resetConversation()
        #expect(container.messages.isEmpty)
        #expect(container.sidebarThreads.count == 1)
        #expect(container.sidebarThreads.first?.title == "persist in sidebar")

        container.stopActiveRequest()
    }

    @Test("Sidebar title remains stable after subsequent messages in same conversation")
    func sidebarTitleStableWithinSameConversation() throws {
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

        let firstPrompt = "first topic title"
        container.sendDraft(firstPrompt)

        let firstThread = try #require(container.sidebarThreads.first)
        let firstTitle = firstThread.title
        let firstActivityAt = firstThread.lastActivityAt
        #expect(firstTitle == ConversationSidebarTitleFormatter.topicTitle(from: firstPrompt))

        container.sendDraft("second prompt should not replace title")

        #expect(container.sidebarThreads.count == 1)
        let updatedThread = try #require(container.sidebarThreads.first)
        #expect(updatedThread.id == firstThread.id)
        #expect(updatedThread.title == firstTitle)
        #expect(updatedThread.lastActivityAt >= firstActivityAt)

        container.stopActiveRequest()
    }

    @Test("New conversation inserts latest sidebar thread at top and keeps previous history")
    func newConversationInsertsThreadAtTop() throws {
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

        let firstPrompt = "first conversation topic"
        container.sendDraft(firstPrompt)

        let firstThread = try #require(container.sidebarThreads.first)

        container.resetConversation()
        let secondPrompt = "second conversation topic"
        container.sendDraft(secondPrompt)

        #expect(container.sidebarThreads.count == 2)
        let topThread = try #require(container.sidebarThreads.first)
        let secondThread = try #require(container.sidebarThreads.dropFirst().first)
        #expect(topThread.id != firstThread.id)
        #expect(topThread.title == ConversationSidebarTitleFormatter.topicTitle(from: secondPrompt))
        #expect(secondThread.id == firstThread.id)
        #expect(secondThread.title == firstThread.title)

        container.stopActiveRequest()
    }

    @Test("deleteAllChatHistory invalidates in-flight sidebar pagination results")
    func deleteAllChatHistoryInvalidatesInFlightSidebarPagination() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        for index in 0 ..< 13 {
            let conversationID = try coordinator.createNewConversation()
            let message = ChatMessage(
                role: .user,
                content: "topic-\(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(2000 + index))
            )
            try coordinator.persistUserMessage(message, conversationId: conversationID)
        }

        let firstPage = try coordinator.fetchSidebarThreadsPage(cursor: nil, limit: 10)

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            sidebarThreads: firstPage.threads,
            hasMoreSidebarThreads: firstPage.hasMore,
            sidebarThreadsCursor: firstPage.nextCursor
        )

        container.sidebarThreadsLoadApplyDelayOverride = .milliseconds(120)

        let loadTask = Task {
            await container.loadMoreSidebarThreadsIfNeeded()
        }

        try await Task.sleep(for: .milliseconds(20))
        await container.deleteAllChatHistory()
        _ = await loadTask.value

        #expect(container.sidebarThreads.isEmpty)
        #expect(!container.hasMoreSidebarThreads)
        #expect(!container.isLoadingMoreSidebarThreads)
        #expect(container.statusMessage == "All chat history cleared")
    }

    @Test("activateConversation applies cached snapshot immediately for smooth switch")
    func activateConversationAppliesCachedSnapshotImmediately() async throws {
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

        container.resetConversation()
        container.sendDraft("conversation B")
        try await waitForRequestToSettle(container)
        let conversationB = try #require(container.activeConversationId)

        // Warm A by switching once so it exists in cache.
        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)
        #expect(container.activeConversationId == conversationA)
        #expect(container.messages.contains { $0.content == "conversation A" })

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        #expect(container.activeConversationId == conversationB)
        #expect(container.messages.contains { $0.content == "conversation B" })
    }

    @Test("activateConversation still refreshes from persistence and returns latest data")
    func activateConversationRefreshesFromPersistence() async throws {
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

        container.resetConversation()
        container.sendDraft("conversation B")
        try await waitForRequestToSettle(container)
        let conversationB = try #require(container.activeConversationId)

        // Prime cache entry for conversation A.
        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)

        let newestPersisted = ChatMessage(role: .assistant, content: "conversation A newest persisted")
        try coordinator.persistSystemMessage(
            newestPersisted,
            conversationId: conversationA,
            status: .completed
        )

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)

        container.activateConversation(conversationId: conversationA)

        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if container.messages.contains(where: { $0.content == newestPersisted.content }) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(container.activeConversationId == conversationA)
        #expect(container.messages.contains { $0.content == newestPersisted.content })
    }

    @Test("Cache does not grow when older pages loaded")
    func cacheDoesNotGrowWhenOlderPagesLoaded() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let totalMessages = RuntimeConstants.conversationMessagePageSize * 3
        for index in 0 ..< totalMessages {
            let role: ChatRole = (index % 2 == 0) ? .user : .assistant
            let message = ChatMessage(
                role: role,
                content: "A-\(index)",
                createdAt: base.addingTimeInterval(Double(index))
            )
            if role == .user {
                try coordinator.persistUserMessage(message, conversationId: conversationA)
            } else {
                try coordinator.persistSystemMessage(message, conversationId: conversationA, status: .completed)
            }
        }

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationB
        )

        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)
        #expect(container.messages.count == RuntimeConstants.conversationMessagePageSize)

        let loadedOlder = await container.loadOlderMessagesIfNeeded()
        #expect(loadedOlder)
        #expect(container.messages.count > RuntimeConstants.conversationMessagePageSize)

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)

        container.activateConversation(conversationId: conversationA)
        #expect(container.messages.count == RuntimeConstants.conversationMessagePageSize)
        try await waitForConversationReady(container, conversationId: conversationA)
    }

    @Test("startup prewarm loads latest configured non-active conversations only")
    func startupPrewarmLoadsTwoRecentConversations() async throws {
        let (container, sidebarThreads) = try makeContainerForStartupPrewarmScenarios()
        #expect(sidebarThreads.count >= RenderConstants.startupPrewarmConversationCount + 1)

        await container.runStartupPrewarmForTesting()

        let cached = Set(container.cachedConversationIDsForTesting)
        let nonActive = sidebarThreads.map(\.id).filter { $0 != container.activeConversationId }
        let expectedPrewarmed = Set(nonActive.prefix(RenderConstants.startupPrewarmConversationCount))
        let nonPrewarmed = nonActive[RenderConstants.startupPrewarmConversationCount]

        #expect(expectedPrewarmed.isSubset(of: cached))
        #expect(!cached.contains(nonPrewarmed))
    }

    @Test("switch to prewarmed conversation uses ready path immediately")
    func prewarmedConversationSwitchUsesReadyPathImmediately() async throws {
        let (container, sidebarThreads) = try makeContainerForStartupPrewarmScenarios()
        let targetConversation = try #require(sidebarThreads.first?.id)

        await container.runStartupPrewarmForTesting()
        container.activateConversation(conversationId: targetConversation)

        #expect(container.statusMessage == "Ready")
    }

    private func makeContainerForStartupPrewarmScenarios() throws -> (AppContainer, [ConversationSidebarThread]) {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let activeConversationId = try coordinator.createNewConversation()
        let recentConversations = try makeRecentConversations(in: coordinator)
        let sidebarThreads = try coordinator.fetchSidebarThreadsPage(cursor: nil, limit: 10).threads
        #expect(sidebarThreads.count >= 3)
        #expect(Set(sidebarThreads.map(\.id)).isSuperset(of: Set(recentConversations)))

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: activeConversationId,
            messages: [],
            sidebarThreads: sidebarThreads
        )
        return (container, sidebarThreads)
    }

    private func makeRecentConversations(in coordinator: ChatPersistenceCoordinator) throws -> [String] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var ids: [String] = []

        for index in 0 ..< (RenderConstants.startupPrewarmConversationCount + 2) {
            let conversationId = try coordinator.createNewConversation()
            let user = ChatMessage(
                role: .user,
                content: "prewarm user \(index)",
                createdAt: base.addingTimeInterval(Double(index * 10 + 1))
            )
            let assistant = ChatMessage(
                role: .assistant,
                content: "prewarm assistant \(index) " + String(repeating: "x", count: 2200),
                createdAt: base.addingTimeInterval(Double(index * 10 + 2))
            )

            try coordinator.persistUserMessage(user, conversationId: conversationId)
            try coordinator.persistSystemMessage(
                assistant,
                conversationId: conversationId,
                status: .completed
            )
            ids.append(conversationId)
        }

        return ids
    }
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

private struct LateEventProvider: LLMProvider {
    let id: String = "mock"

    func availableModels(context _: ProviderInvocationContext) async throws -> [ModelDescriptor] {
        await Task.yield()
        return [
            ModelDescriptor(
                id: "mock-text-1",
                displayName: "Mock Text v1",
                capabilities: [.text]
            )
        ]
    }

    func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage {
        await Task.yield()
        return ChatMessage(role: .assistant, content: "unused")
    }

    func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: requestID))
            continuation.yield(.delta(requestID: requestID, text: "A"))
            continuation.yield(.completed(requestID: requestID))
            // Provider bug simulation: stale delta emitted after terminal.
            continuation.yield(.delta(requestID: requestID, text: "B"))
            continuation.finish()
        }
    }
}
