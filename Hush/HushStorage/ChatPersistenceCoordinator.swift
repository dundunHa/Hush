import Foundation
import GRDB
import os

// MARK: - Chat Persistence Coordinator

struct MessagePage: Sendable, Equatable {
    let messages: [ChatMessage]
    let hasMoreOlderMessages: Bool
    let oldestOrderIndex: Int?
    let newestOrderIndex: Int?
}

struct SidebarThreadsCursor: Sendable, Equatable {
    let lastActivityAt: Date
    let conversationID: String
}

struct SidebarThreadsPage: Sendable, Equatable {
    let threads: [ConversationSidebarThread]
    let hasMore: Bool
    let nextCursor: SidebarThreadsCursor?
}

struct BootstrapState: Sendable, Equatable {
    let conversationID: String
    let messagePage: MessagePage
}

/// Coordinates chat persistence operations between the UI layer and the database.
/// Manages conversation lifecycle, message persistence, streaming throttling,
/// and crash recovery.
///
/// Thread safety: This type is designed to be used from `@MainActor` context
/// via `AppContainer`. The underlying GRDB operations are thread-safe.
private let persistenceLogger = Logger(subsystem: "com.hush.app", category: "Persistence")

public final class ChatPersistenceCoordinator: Sendable {
    private let dbManager: DatabaseManager
    private let conversationRepo: GRDBConversationRepository
    private let messageRepo: GRDBMessageRepository
    private let outboxRepo: GRDBSyncOutboxRepository
    private struct SidebarThreadRow: FetchableRecord, Decodable {
        let id: String
        let title: String?
        let createdAt: Date
        let lastActivityAt: Date
        let firstUserContent: String?
    }

    // MARK: - Init

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
        conversationRepo = GRDBConversationRepository(dbManager: dbManager)
        messageRepo = GRDBMessageRepository(dbManager: dbManager)
        outboxRepo = GRDBSyncOutboxRepository(dbManager: dbManager)
    }

    // MARK: - Bootstrap

    /// Performs crash recovery and returns the active conversation + limited messages.
    /// If no conversation exists, creates a new one.
    ///
    /// - Parameters:
    ///   - messageLimit: Maximum number of messages to load for the active conversation.
    /// - Returns: Tuple of (conversationId, messages as ChatMessage array)
    public func bootstrap(messageLimit: Int = 9) throws -> (conversationId: String, messages: [ChatMessage]) {
        let state = try bootstrapState(messageLimit: messageLimit)
        return (state.conversationID, state.messagePage.messages)
    }

    func bootstrapState(messageLimit: Int = 9) throws -> BootstrapState {
        // Step 1: Finalize any interrupted streaming messages from previous session
        try messageRepo.finalizeInterruptedMessages()

        // Step 2: Load or create active conversation
        let conversation: ConversationRecord
        if let existing = try conversationRepo.fetchMostRecent() {
            conversation = existing
        } else {
            let newConversation = ConversationRecord()
            try conversationRepo.create(newConversation)
            conversation = newConversation
        }

        // Step 3: Load limited messages for active conversation
        let messagePage = try fetchMessagePage(
            conversationId: conversation.id,
            beforeOrderIndex: nil,
            limit: messageLimit
        )

        return BootstrapState(
            conversationID: conversation.id,
            messagePage: messagePage
        )
    }

    // MARK: - Conversation Lifecycle

    /// Creates a new conversation and returns its ID.
    /// Used by "Clear Chat" to start fresh while retaining old data.
    public func createNewConversation() throws -> String {
        let conversation = ConversationRecord()
        try conversationRepo.create(conversation)
        return conversation.id
    }

    /// Soft-deletes a conversation and all its associated messages.
    /// Both the conversation record and its messages get `deletedAt` set.
    public func deleteConversation(id: String) throws {
        try messageRepo.softDeleteMessages(conversationId: id)
        try conversationRepo.softDelete(id: id)
    }

    public func archiveConversation(id: String) throws {
        try conversationRepo.setArchived(id: id, isArchived: true)
    }

    public func unarchiveConversation(id: String) throws {
        try conversationRepo.setArchived(id: id, isArchived: false)
    }

    nonisolated func fetchArchivedThreads() throws -> [ConversationSidebarThread] {
        let sql = """
        WITH firstUser AS (
            SELECT m.conversationId AS conversationId, m.content AS firstUserContent
            FROM messages m
            INNER JOIN (
                SELECT conversationId, MIN(orderIndex) AS firstUserOrderIndex
                FROM messages
                WHERE deletedAt IS NULL
                  AND role = ?
                GROUP BY conversationId
            ) idx
                ON idx.conversationId = m.conversationId
               AND idx.firstUserOrderIndex = m.orderIndex
            WHERE m.deletedAt IS NULL
              AND m.role = ?
        )
        SELECT
            c.id AS id,
            c.title AS title,
            c.createdAt AS createdAt,
            c.updatedAt AS lastActivityAt,
            firstUser.firstUserContent AS firstUserContent
        FROM conversations c
        LEFT JOIN firstUser ON firstUser.conversationId = c.id
        WHERE c.deletedAt IS NULL
          AND c.isArchived = 1
        ORDER BY c.updatedAt DESC
        """

        return try dbManager.read { db in
            let rows = try SidebarThreadRow.fetchAll(
                db,
                sql: sql,
                arguments: [ChatRole.user.rawValue, ChatRole.user.rawValue]
            )
            return rows.map { row in
                ConversationSidebarThread(
                    id: row.id,
                    title: ConversationSidebarTitleFormatter.makeTitle(
                        conversationTitle: row.title,
                        firstUserContent: row.firstUserContent
                    ),
                    lastActivityAt: row.lastActivityAt
                )
            }
        }
    }

    // MARK: - Message Persistence

    /// Returns conversation threads for sidebar display.
    /// Threads are ordered by last message activity (newest first).
    nonisolated func fetchSidebarThreads(limit: Int = 200) throws -> [ConversationSidebarThread] {
        try fetchSidebarThreadsPage(cursor: nil, limit: limit).threads
    }

    nonisolated func fetchSidebarThreadsPage(
        cursor: SidebarThreadsCursor?,
        limit: Int = 10
    ) throws -> SidebarThreadsPage {
        guard limit > 0 else {
            return SidebarThreadsPage(threads: [], hasMore: false, nextCursor: nil)
        }

        let query = sidebarThreadsPageQuery(cursor: cursor, limit: limit)

        return try dbManager.read { db in
            let rows = try SidebarThreadRow.fetchAll(
                db,
                sql: query.sql,
                arguments: query.arguments
            )
            return makeSidebarThreadsPage(rows: rows, limit: limit)
        }
    }

    private nonisolated func sidebarThreadsPageQuery(
        cursor: SidebarThreadsCursor?,
        limit: Int
    ) -> (sql: String, arguments: StatementArguments) {
        var sql = """
        WITH lastMessage AS (
            SELECT conversationId, MAX(createdAt) AS lastMessageAt
            FROM messages
            WHERE deletedAt IS NULL
            GROUP BY conversationId
        ),
        firstUser AS (
            SELECT m.conversationId AS conversationId, m.content AS firstUserContent
            FROM messages m
            INNER JOIN (
                SELECT conversationId, MIN(orderIndex) AS firstUserOrderIndex
                FROM messages
                WHERE deletedAt IS NULL
                  AND role = ?
                GROUP BY conversationId
            ) idx
                ON idx.conversationId = m.conversationId
               AND idx.firstUserOrderIndex = m.orderIndex
            WHERE m.deletedAt IS NULL
              AND m.role = ?
        )
        SELECT
            c.id AS id,
            c.title AS title,
            c.createdAt AS createdAt,
            COALESCE(lastMessage.lastMessageAt, c.createdAt) AS lastActivityAt,
            firstUser.firstUserContent AS firstUserContent
        FROM conversations c
        LEFT JOIN lastMessage ON lastMessage.conversationId = c.id
        INNER JOIN firstUser ON firstUser.conversationId = c.id
        WHERE c.deletedAt IS NULL
          AND c.isArchived = 0
        """

        var arguments: StatementArguments = [
            ChatRole.user.rawValue,
            ChatRole.user.rawValue
        ]

        if let cursor {
            sql += "\n"
            sql += """
              AND (
                COALESCE(lastMessage.lastMessageAt, c.createdAt) < ?
                OR (
                    COALESCE(lastMessage.lastMessageAt, c.createdAt) = ?
                    AND c.id < ?
                )
              )
            """
            arguments += [cursor.lastActivityAt, cursor.lastActivityAt, cursor.conversationID]
        }

        sql += "\n"
        sql += """
        ORDER BY lastActivityAt DESC, id DESC
        LIMIT ?
        """
        arguments += [limit + 1]

        return (sql, arguments)
    }

    private nonisolated func makeSidebarThreadsPage(
        rows: [SidebarThreadRow],
        limit: Int
    ) -> SidebarThreadsPage {
        let hasMore = rows.count > limit
        let pageRows = hasMore ? Array(rows.prefix(limit)) : rows
        let threads = pageRows.map { row in
            ConversationSidebarThread(
                id: row.id,
                title: ConversationSidebarTitleFormatter.makeTitle(
                    conversationTitle: row.title,
                    firstUserContent: row.firstUserContent
                ),
                lastActivityAt: row.lastActivityAt
            )
        }

        let nextCursor = pageRows.last.map {
            SidebarThreadsCursor(
                lastActivityAt: $0.lastActivityAt,
                conversationID: $0.id
            )
        }

        return SidebarThreadsPage(
            threads: threads,
            hasMore: hasMore,
            nextCursor: nextCursor
        )
    }

    /// Loads persisted messages for a conversation.
    nonisolated func fetchMessages(conversationId: String, limit: Int? = nil) throws -> [ChatMessage] {
        if let limit {
            return try fetchMessagePage(
                conversationId: conversationId,
                beforeOrderIndex: nil,
                limit: limit
            ).messages
        }

        let records = try messageRepo.fetchMessages(conversationId: conversationId, limit: nil)
        return records.map(mapRecordToChatMessage)
    }

    nonisolated func fetchMessagePage(
        conversationId: String,
        beforeOrderIndex: Int?,
        limit: Int = 9
    ) throws -> MessagePage {
        let page = try messageRepo.fetchMessagesPage(
            conversationId: conversationId,
            beforeOrderIndex: beforeOrderIndex,
            limit: limit
        )
        return MessagePage(
            messages: page.records.map(mapRecordToChatMessage),
            hasMoreOlderMessages: page.hasMoreOlder,
            oldestOrderIndex: page.oldestOrderIndex,
            newestOrderIndex: page.newestOrderIndex
        )
    }

    private nonisolated func mapRecordToChatMessage(_ record: MessageRecord) -> ChatMessage {
        ChatMessage(
            id: UUID(uuidString: record.id) ?? UUID(),
            role: ChatRole(rawValue: record.role) ?? .assistant,
            content: record.content,
            createdAt: record.createdAt
        )
    }

    /// Returns persisted user messages for sidebar history display.
    /// Messages are ordered from newest to oldest across all non-deleted conversations.
    public func fetchSidebarUserMessages(limit: Int = 500) throws -> [ChatMessage] {
        try dbManager.read { db in
            let records = try MessageRecord.fetchAll(
                db,
                sql: """
                SELECT m.*
                FROM messages m
                INNER JOIN conversations c ON c.id = m.conversationId
                WHERE m.deletedAt IS NULL
                  AND c.deletedAt IS NULL
                  AND m.role = ?
                ORDER BY m.createdAt DESC, m.orderIndex DESC
                LIMIT ?
                """,
                arguments: [ChatRole.user.rawValue, limit]
            )
            return records.compactMap { record in
                guard let id = UUID(uuidString: record.id) else {
                    return nil
                }
                return ChatMessage(
                    id: id,
                    role: .user,
                    content: record.content,
                    createdAt: record.createdAt
                )
            }
        }
    }

    /// Persists an accepted user message atomically.
    /// Called when a submission is accepted (not queue-full rejected).
    ///
    /// - Parameters:
    ///   - message: The ChatMessage to persist.
    ///   - conversationId: The active conversation ID.
    public func persistUserMessage(_ message: ChatMessage, conversationId: String) throws {
        let orderIndex = try messageRepo.nextOrderIndex(conversationId: conversationId)
        let record = MessageRecord(
            id: message.id.uuidString,
            conversationId: conversationId,
            role: message.role.rawValue,
            content: message.content,
            status: .final_,
            orderIndex: orderIndex,
            createdAt: message.createdAt
        )
        try messageRepo.insert(record)
    }

    /// Creates an initial draft assistant message record on first streaming delta.
    ///
    /// - Parameters:
    ///   - message: The ChatMessage with initial content.
    ///   - conversationId: The active conversation ID.
    ///   - requestId: The correlated request ID.
    public func persistAssistantDraft(
        _ message: ChatMessage,
        conversationId: String,
        requestId: String
    ) throws {
        let orderIndex = try messageRepo.nextOrderIndex(conversationId: conversationId)
        let record = MessageRecord(
            id: message.id.uuidString,
            conversationId: conversationId,
            role: ChatRole.assistant.rawValue,
            content: message.content,
            status: .streaming,
            requestId: requestId,
            orderIndex: orderIndex,
            createdAt: message.createdAt
        )
        try messageRepo.insert(record)
    }

    /// Updates the content of a streaming assistant message (throttled writes).
    ///
    /// - Parameters:
    ///   - messageId: The message UUID string.
    ///   - content: The accumulated content so far.
    public func updateStreamingContent(messageId: String, content: String) throws {
        guard var record = try messageRepo.fetchByRequestId(messageId) else {
            // Try by message ID directly
            try dbManager.write { db in
                try db.execute(
                    sql: """
                    UPDATE messages SET content = ?, updatedAt = ?
                    WHERE id = ? AND status = ?
                    """,
                    arguments: [content, Date.now, messageId, MessageStatus.streaming.rawValue]
                )
            }
            return
        }
        record.content = content
        try messageRepo.update(record)
    }

    /// Finalizes an assistant message with a terminal state.
    ///
    /// - Parameters:
    ///   - messageId: The message UUID string.
    ///   - content: The final content.
    ///   - status: The terminal status.
    public func finalizeAssistantMessage(
        messageId: String,
        content: String,
        status: MessageStatus
    ) throws {
        try dbManager.write { db in
            try db.execute(
                sql: """
                UPDATE messages
                SET content = ?, status = ?, updatedAt = ?, syncState = ?
                WHERE id = ?
                """,
                arguments: [content, status.rawValue, Date.now, SyncState.pending.rawValue, messageId]
            )

            // Outbox entry for the update
            let outbox = SyncOutboxRecord(
                entityType: "message",
                entityId: messageId,
                operationType: .update
            )
            try outbox.insert(db)
        }
    }

    /// Persists a system-generated message (e.g., error, stopped placeholder).
    ///
    /// - Parameters:
    ///   - message: The ChatMessage to persist.
    ///   - conversationId: The active conversation ID.
    ///   - status: The message status.
    public func persistSystemMessage(
        _ message: ChatMessage,
        conversationId: String,
        status: MessageStatus
    ) throws {
        let orderIndex = try messageRepo.nextOrderIndex(conversationId: conversationId)
        let record = MessageRecord(
            id: message.id.uuidString,
            conversationId: conversationId,
            role: message.role.rawValue,
            content: message.content,
            status: status,
            orderIndex: orderIndex,
            createdAt: message.createdAt
        )
        try messageRepo.insert(record)
    }
}

// MARK: - Data Management

extension ChatPersistenceCoordinator {
    /// Returns the total file size of the SQLite database (main + WAL + SHM) in bytes.
    nonisolated func databaseFileSize() -> UInt64 {
        let path = dbManager.databasePath
        let walPath = path + "-wal"
        let shmPath = path + "-shm"

        var total: UInt64 = 0
        for filePath in [path, walPath, shmPath] {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? UInt64
            {
                total += size
            }
        }
        return total
    }

    /// Returns the total number of non-deleted conversations.
    nonisolated func conversationCount() throws -> Int {
        try dbManager.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM conversations WHERE deletedAt IS NULL"
            ) ?? 0
        }
    }

    /// Returns the total number of non-deleted messages.
    nonisolated func messageCount() throws -> Int {
        try dbManager.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM messages WHERE deletedAt IS NULL"
            ) ?? 0
        }
    }

    /// Hard-deletes all conversations, messages, and outbox entries, then reclaims disk space.
    nonisolated func deleteAllChatData() throws {
        try dbManager.write { db in
            try db.execute(sql: "DELETE FROM syncOutbox")
            try db.execute(sql: "DELETE FROM messages")
            try db.execute(sql: "DELETE FROM conversations")
        }
        do {
            try dbManager.vacuum()
        } catch {
            persistenceLogger.warning("VACUUM failed after clearing data: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns pending outbox entries for future sync worker consumption.
    public func pendingOutboxEntries(limit: Int = 50) throws -> [SyncOutboxRecord] {
        try outboxRepo.fetchPending(limit: limit)
    }
}
