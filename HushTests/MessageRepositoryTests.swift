import Foundation
import GRDB
@testable import Hush
import Testing

// MARK: - 6.1 Repository Tests: Messages, Ordering, Terminal States

@Suite("Message Repository Tests")
struct MessageRepositoryTests {
    private func makeSetup() throws -> (GRDBMessageRepository, GRDBConversationRepository, DatabaseManager, String) {
        let db = try DatabaseManager.inMemory()
        let messageRepo = GRDBMessageRepository(dbManager: db)
        let convRepo = GRDBConversationRepository(dbManager: db)

        let conv = ConversationRecord(title: "Test")
        try convRepo.create(conv)

        return (messageRepo, convRepo, db, conv.id)
    }

    @Test("Insert and fetch messages in order")
    func insertAndFetchInOrder() throws {
        let (repo, _, _, convId) = try makeSetup()

        let msg1 = MessageRecord(
            conversationId: convId,
            role: "user",
            content: "Hello",
            orderIndex: 0
        )
        let msg2 = MessageRecord(
            conversationId: convId,
            role: "assistant",
            content: "Hi there",
            orderIndex: 1
        )

        try repo.insert(msg1)
        try repo.insert(msg2)

        let messages = try repo.fetchMessages(conversationId: convId)
        #expect(messages.count == 2)
        #expect(messages[0].role == "user")
        #expect(messages[1].role == "assistant")
        #expect(messages[0].orderIndex < messages[1].orderIndex)
    }

    @Test("Fetch with limit returns newest messages in chronological order")
    func fetchWithLimitReturnsNewestMessages() throws {
        let (repo, _, _, convId) = try makeSetup()

        for orderIndex in 0 ..< 5 {
            let message = MessageRecord(
                conversationId: convId,
                role: orderIndex.isMultiple(of: 2) ? "user" : "assistant",
                content: "message-\(orderIndex)",
                orderIndex: orderIndex
            )
            try repo.insert(message)
        }

        let messages = try repo.fetchMessages(conversationId: convId, limit: 3)
        #expect(messages.count == 3)
        #expect(messages.map(\.orderIndex) == [2, 3, 4])
    }

    @Test("Fetch message page supports older pagination without overlap")
    func fetchMessagesPagePaginatesOlderMessages() throws {
        let (repo, _, _, convId) = try makeSetup()

        for orderIndex in 0 ..< 12 {
            let message = MessageRecord(
                conversationId: convId,
                role: orderIndex.isMultiple(of: 2) ? "user" : "assistant",
                content: "message-\(orderIndex)",
                orderIndex: orderIndex
            )
            try repo.insert(message)
        }

        let firstPage = try repo.fetchMessagesPage(
            conversationId: convId,
            beforeOrderIndex: nil,
            limit: 5
        )
        #expect(firstPage.records.map(\.orderIndex) == [7, 8, 9, 10, 11])
        #expect(firstPage.hasMoreOlder)
        #expect(firstPage.oldestOrderIndex == 7)
        #expect(firstPage.newestOrderIndex == 11)

        let secondPage = try repo.fetchMessagesPage(
            conversationId: convId,
            beforeOrderIndex: firstPage.oldestOrderIndex,
            limit: 5
        )
        #expect(secondPage.records.map(\.orderIndex) == [2, 3, 4, 5, 6])
        #expect(secondPage.hasMoreOlder)

        let thirdPage = try repo.fetchMessagesPage(
            conversationId: convId,
            beforeOrderIndex: secondPage.oldestOrderIndex,
            limit: 5
        )
        #expect(thirdPage.records.map(\.orderIndex) == [0, 1])
        #expect(!thirdPage.hasMoreOlder)
    }

    @Test("Next order index increments correctly")
    func nextOrderIndex() throws {
        let (repo, _, _, convId) = try makeSetup()

        let first = try repo.nextOrderIndex(conversationId: convId)
        #expect(first == 0)

        let msg = MessageRecord(
            conversationId: convId,
            role: "user",
            content: "Test",
            orderIndex: first
        )
        try repo.insert(msg)

        let second = try repo.nextOrderIndex(conversationId: convId)
        #expect(second == 1)
    }

    @Test("Update message content and status")
    func updateMessage() throws {
        let (repo, _, _, convId) = try makeSetup()

        var msg = MessageRecord(
            conversationId: convId,
            role: "assistant",
            content: "Partial",
            status: .streaming,
            orderIndex: 0
        )
        try repo.insert(msg)

        msg.content = "Partial response complete"
        msg.status = .completed
        try repo.update(msg)

        let messages = try repo.fetchMessages(conversationId: convId)
        #expect(messages.count == 1)
        #expect(messages[0].content == "Partial response complete")
        #expect(messages[0].status == .completed)
    }

    @Test("Fetch by request ID")
    func fetchByRequestId() throws {
        let (repo, _, _, convId) = try makeSetup()

        let requestId = UUID().uuidString
        let msg = MessageRecord(
            conversationId: convId,
            role: "assistant",
            content: "Streaming...",
            status: .streaming,
            requestId: requestId,
            orderIndex: 0
        )
        try repo.insert(msg)

        let fetched = try repo.fetchByRequestId(requestId)
        #expect(fetched != nil)
        #expect(fetched?.id == msg.id)
    }

    @Test("Finalize interrupted messages on recovery")
    func finalizeInterruptedMessages() throws {
        let (repo, _, _, convId) = try makeSetup()

        // Create a message in streaming state (simulating crash before terminal)
        let msg = MessageRecord(
            conversationId: convId,
            role: "assistant",
            content: "Partial streaming content",
            status: .streaming,
            requestId: UUID().uuidString,
            orderIndex: 0
        )
        try repo.insert(msg)

        // Simulate crash recovery
        try repo.finalizeInterruptedMessages()

        let messages = try repo.fetchMessages(conversationId: convId)
        #expect(messages.count == 1)
        #expect(messages[0].status == .interrupted)
        #expect(messages[0].content == "Partial streaming content")
    }

    @Test("Terminal state durability: completed message survives read")
    func terminalStateDurability() throws {
        let (repo, _, _, convId) = try makeSetup()

        var msg = MessageRecord(
            conversationId: convId,
            role: "assistant",
            content: "Final answer",
            status: .streaming,
            orderIndex: 0
        )
        try repo.insert(msg)

        msg.content = "Final answer"
        msg.status = .completed
        try repo.update(msg)

        // Re-read
        let messages = try repo.fetchMessages(conversationId: convId)
        #expect(messages[0].status == .completed)
        #expect(messages[0].content == "Final answer")
    }

    @Test("Deleted messages excluded from fetch")
    func deletedMessagesExcluded() throws {
        let (repo, _, db, convId) = try makeSetup()

        let msg = MessageRecord(
            conversationId: convId,
            role: "user",
            content: "To delete",
            orderIndex: 0
        )
        try repo.insert(msg)

        // Soft-delete directly
        try db.write { db in
            try db.execute(
                sql: "UPDATE messages SET deletedAt = ? WHERE id = ?",
                arguments: [Date.now, msg.id]
            )
        }

        let messages = try repo.fetchMessages(conversationId: convId)
        #expect(messages.isEmpty)
    }

    @Test("Insert generates outbox entry")
    func insertGeneratesOutbox() throws {
        let (repo, _, db, convId) = try makeSetup()

        let msg = MessageRecord(
            conversationId: convId,
            role: "user",
            content: "Outbox test",
            orderIndex: 0
        )
        try repo.insert(msg)

        let count = try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM syncOutbox WHERE entityType = ? AND entityId = ?",
                arguments: ["message", msg.id]
            )
        }
        #expect(count == 1)
    }
}
