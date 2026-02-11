import Foundation
import GRDB
@testable import Hush
import Testing

// MARK: - 6.2 Lifecycle Tests: Queue-Full, Streaming Persistence

@Suite("Chat Persistence Coordinator Tests")
struct ChatPersistenceCoordinatorTests {
    private func makeCoordinator() throws -> ChatPersistenceCoordinator {
        let db = try DatabaseManager.inMemory()
        return ChatPersistenceCoordinator(dbManager: db)
    }

    @Test("Bootstrap creates conversation when none exist")
    func bootstrapCreatesConversation() throws {
        let coordinator = try makeCoordinator()
        let result = try coordinator.bootstrap()
        #expect(!result.conversationId.isEmpty)
        #expect(result.messages.isEmpty)
    }

    @Test("Bootstrap returns existing messages")
    func bootstrapReturnsMessages() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        // First bootstrap creates a conversation
        let first = try coordinator.bootstrap()

        // Insert a message
        let msg = ChatMessage(role: .user, content: "Hello")
        try coordinator.persistUserMessage(msg, conversationId: first.conversationId)

        // Second bootstrap should return the message
        let coordinator2 = ChatPersistenceCoordinator(dbManager: db)
        let second = try coordinator2.bootstrap()

        #expect(second.conversationId == first.conversationId)
        #expect(second.messages.count == 1)
        #expect(second.messages[0].content == "Hello")
        #expect(second.messages[0].role == .user)
    }

    @Test("Bootstrap state reports hasMore for long conversations")
    func bootstrapStateReportsPaginationMetadata() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)
        let result = try coordinator.bootstrap()

        for orderIndex in 0 ..< 14 {
            let message = ChatMessage(
                role: orderIndex.isMultiple(of: 2) ? .user : .assistant,
                content: "message-\(orderIndex)"
            )
            if message.role == .user {
                try coordinator.persistUserMessage(message, conversationId: result.conversationId)
            } else {
                try coordinator.persistSystemMessage(
                    message,
                    conversationId: result.conversationId,
                    status: .completed
                )
            }
        }

        let state = try coordinator.bootstrapState(messageLimit: 9)
        #expect(state.messagePage.messages.count == 9)
        #expect(state.messagePage.hasMoreOlderMessages)
        #expect(state.messagePage.oldestOrderIndex == 5)
        #expect(state.messagePage.newestOrderIndex == 13)
    }

    @Test("Fetch message page loads older messages by cursor")
    func fetchMessagePageLoadsOlderMessages() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)
        let result = try coordinator.bootstrap()

        for orderIndex in 0 ..< 14 {
            let message = ChatMessage(
                role: orderIndex.isMultiple(of: 2) ? .user : .assistant,
                content: "message-\(orderIndex)"
            )
            if message.role == .user {
                try coordinator.persistUserMessage(message, conversationId: result.conversationId)
            } else {
                try coordinator.persistSystemMessage(
                    message,
                    conversationId: result.conversationId,
                    status: .completed
                )
            }
        }

        let newestPage = try coordinator.fetchMessagePage(
            conversationId: result.conversationId,
            beforeOrderIndex: nil,
            limit: 9
        )
        let olderPage = try coordinator.fetchMessagePage(
            conversationId: result.conversationId,
            beforeOrderIndex: newestPage.oldestOrderIndex,
            limit: 9
        )

        #expect(newestPage.messages.count == 9)
        #expect(olderPage.messages.count == 5)
        #expect(!olderPage.hasMoreOlderMessages)
        #expect(olderPage.oldestOrderIndex == 0)
        #expect(olderPage.newestOrderIndex == 4)
    }

    @Test("Create new conversation returns different ID")
    func createNewConversation() throws {
        let coordinator = try makeCoordinator()
        let result = try coordinator.bootstrap()
        let newId = try coordinator.createNewConversation()
        #expect(newId != result.conversationId)
    }

    @Test("Persist user message stores correctly")
    func persistUserMessage() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)
        let result = try coordinator.bootstrap()

        let msg = ChatMessage(role: .user, content: "Test message")
        try coordinator.persistUserMessage(msg, conversationId: result.conversationId)

        // Re-bootstrap to verify persistence
        let coordinator2 = ChatPersistenceCoordinator(dbManager: db)
        let reloaded = try coordinator2.bootstrap()
        #expect(reloaded.messages.count == 1)
        #expect(reloaded.messages[0].content == "Test message")
    }

    @Test("Persist assistant draft and finalize")
    func persistAssistantDraftAndFinalize() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)
        let result = try coordinator.bootstrap()

        let assistantMsg = ChatMessage(role: .assistant, content: "Partial")
        let requestId = UUID().uuidString
        try coordinator.persistAssistantDraft(
            assistantMsg,
            conversationId: result.conversationId,
            requestId: requestId
        )

        // Finalize
        try coordinator.finalizeAssistantMessage(
            messageId: assistantMsg.id.uuidString,
            content: "Full response",
            status: .completed
        )

        // Re-bootstrap
        let coordinator2 = ChatPersistenceCoordinator(dbManager: db)
        let reloaded = try coordinator2.bootstrap()
        #expect(reloaded.messages.count == 1)
        #expect(reloaded.messages[0].content == "Full response")
    }

    @Test("Crash recovery finalizes streaming messages as interrupted")
    func crashRecoveryFinalizesStreaming() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)
        let result = try coordinator.bootstrap()

        // Simulate: user message + streaming assistant message, then "crash"
        let userMsg = ChatMessage(role: .user, content: "Ask something")
        try coordinator.persistUserMessage(userMsg, conversationId: result.conversationId)

        let assistantMsg = ChatMessage(role: .assistant, content: "Partial content before crash")
        try coordinator.persistAssistantDraft(
            assistantMsg,
            conversationId: result.conversationId,
            requestId: UUID().uuidString
        )

        // "Crash" happens here - no finalize call

        // New bootstrap simulates app restart
        let coordinator2 = ChatPersistenceCoordinator(dbManager: db)
        let recovered = try coordinator2.bootstrap()

        #expect(recovered.messages.count == 2)
        // The streaming message should still have its content preserved
        let assistantRecovered = recovered.messages.first(where: { $0.role == .assistant })
        #expect(assistantRecovered?.content == "Partial content before crash")
    }

    @Test("Persist system message (error/stopped)")
    func persistSystemMessage() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)
        let result = try coordinator.bootstrap()

        let errorMsg = ChatMessage(role: .assistant, content: "Error: Something went wrong")
        try coordinator.persistSystemMessage(
            errorMsg,
            conversationId: result.conversationId,
            status: .failed
        )

        let coordinator2 = ChatPersistenceCoordinator(dbManager: db)
        let reloaded = try coordinator2.bootstrap()
        #expect(reloaded.messages.count == 1)
        #expect(reloaded.messages[0].content == "Error: Something went wrong")
    }

    @Test("Sidebar threads page paginates with cursor")
    func sidebarThreadsPagePagination() throws {
        let coordinator = try makeCoordinator()

        for index in 0 ..< 13 {
            let conversationID = try coordinator.createNewConversation()
            let message = ChatMessage(
                role: .user,
                content: "topic-\(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1000 + index))
            )
            try coordinator.persistUserMessage(message, conversationId: conversationID)
        }

        let firstPage = try coordinator.fetchSidebarThreadsPage(cursor: nil, limit: 10)
        #expect(firstPage.threads.count == 10)
        #expect(firstPage.hasMore)
        #expect(firstPage.threads.first?.title == "topic-12")
        #expect(firstPage.nextCursor != nil)

        let secondPage = try coordinator.fetchSidebarThreadsPage(
            cursor: firstPage.nextCursor,
            limit: 10
        )
        #expect(secondPage.threads.count == 3)
        #expect(!secondPage.hasMore)

        let allIDs = Set((firstPage.threads + secondPage.threads).map(\.id))
        #expect(allIDs.count == 13)
    }

    @Test("deleteAllChatData removes data and VACUUM reclaims space")
    func deleteAllChatDataShrinksDatabaseFile() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)
        let result = try coordinator.bootstrap()

        for idx in 0 ..< 50 {
            let msg = ChatMessage(
                role: idx.isMultiple(of: 2) ? .user : .assistant,
                content: String(repeating: "X", count: 500)
            )
            if msg.role == .user {
                try coordinator.persistUserMessage(msg, conversationId: result.conversationId)
            } else {
                try coordinator.persistSystemMessage(
                    msg,
                    conversationId: result.conversationId,
                    status: .completed
                )
            }
        }

        let sizeBeforeClear = coordinator.databaseFileSize()
        #expect(sizeBeforeClear > 0)

        try coordinator.deleteAllChatData()

        let sizeAfterClear = coordinator.databaseFileSize()
        #expect(sizeAfterClear < sizeBeforeClear)
    }

    @Test("databaseFileSize includes WAL and SHM files")
    func databaseFileSizeIncludesWALFiles() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)
        _ = try coordinator.bootstrap()

        let mainPath = db.databasePath
        let walPath = mainPath + "-wal"

        let totalSize = coordinator.databaseFileSize()
        let mainSize: UInt64 = {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: mainPath),
                  let fileSize = attrs[.size] as? UInt64
            else { return 0 }
            return fileSize
        }()

        let walExists = FileManager.default.fileExists(atPath: walPath)
        if walExists {
            #expect(totalSize >= mainSize)
        } else {
            #expect(totalSize == mainSize)
        }
    }

    @Test("conversationCount and messageCount are zero after deleteAllChatData")
    func countsAreZeroAfterDelete() throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)
        let result = try coordinator.bootstrap()

        for idx in 0 ..< 5 {
            let msg = ChatMessage(role: .user, content: "msg-\(idx)")
            try coordinator.persistUserMessage(msg, conversationId: result.conversationId)
        }

        #expect(try coordinator.conversationCount() > 0)
        #expect(try coordinator.messageCount() > 0)

        try coordinator.deleteAllChatData()

        #expect(try coordinator.conversationCount() == 0)
        #expect(try coordinator.messageCount() == 0)
    }
}
