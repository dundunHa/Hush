import Foundation
import GRDB

// MARK: - GRDB Message Repository

/// GRDB-backed implementation of `MessageRepository`.
public final class GRDBMessageRepository: MessageRepository, Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public nonisolated func fetchMessages(conversationId: String, limit: Int? = nil) throws -> [MessageRecord] {
        if let limit {
            return try fetchMessagesPage(
                conversationId: conversationId,
                beforeOrderIndex: nil,
                limit: limit
            ).records
        }

        return try dbManager.read { db in
            try MessageRecord
                .filter(Column("conversationId") == conversationId)
                .filter(Column("deletedAt") == nil)
                .order(Column("orderIndex").asc)
                .fetchAll(db)
        }
    }

    public nonisolated func fetchMessagesPage(
        conversationId: String,
        beforeOrderIndex: Int?,
        limit: Int
    ) throws -> MessageRecordPage {
        guard limit > 0 else {
            return MessageRecordPage(
                records: [],
                hasMoreOlder: false,
                oldestOrderIndex: nil,
                newestOrderIndex: nil
            )
        }

        return try dbManager.read { db in
            let records: [MessageRecord]

            if let beforeOrderIndex {
                records = try MessageRecord.fetchAll(
                    db,
                    sql: """
                    SELECT *
                    FROM messages
                    WHERE conversationId = ?
                      AND deletedAt IS NULL
                      AND orderIndex < ?
                    ORDER BY orderIndex DESC
                    LIMIT ?
                    """,
                    arguments: [conversationId, beforeOrderIndex, limit + 1]
                )
            } else {
                records = try MessageRecord.fetchAll(
                    db,
                    sql: """
                    SELECT *
                    FROM messages
                    WHERE conversationId = ?
                      AND deletedAt IS NULL
                    ORDER BY orderIndex DESC
                    LIMIT ?
                    """,
                    arguments: [conversationId, limit + 1]
                )
            }

            let hasMoreOlder = records.count > limit
            let pageDescending = hasMoreOlder ? Array(records.prefix(limit)) : records
            let pageAscending = pageDescending.sorted { lhs, rhs in
                lhs.orderIndex < rhs.orderIndex
            }

            return MessageRecordPage(
                records: pageAscending,
                hasMoreOlder: hasMoreOlder,
                oldestOrderIndex: pageAscending.first?.orderIndex,
                newestOrderIndex: pageAscending.last?.orderIndex
            )
        }
    }

    public nonisolated func nextOrderIndex(conversationId: String) throws -> Int {
        try dbManager.read { db in
            let maxIndex = try Int.fetchOne(
                db,
                sql: "SELECT MAX(orderIndex) FROM messages WHERE conversationId = ?",
                arguments: [conversationId]
            )
            return (maxIndex ?? -1) + 1
        }
    }

    public func insert(_ message: MessageRecord) throws {
        try dbManager.write { db in
            try message.insert(db)

            // Append outbox entry in same transaction
            let outbox = SyncOutboxRecord(
                entityType: "message",
                entityId: message.id,
                operationType: .insert
            )
            try outbox.insert(db)
        }
    }

    public func update(_ message: MessageRecord) throws {
        try dbManager.write { db in
            var record = message
            record.updatedAt = .now
            record.syncState = .pending
            try record.update(db)

            // Append outbox entry in same transaction
            let outbox = SyncOutboxRecord(
                entityType: "message",
                entityId: message.id,
                operationType: .update
            )
            try outbox.insert(db)
        }
    }

    public nonisolated func fetchByRequestId(_ requestId: String) throws -> MessageRecord? {
        try dbManager.read { db in
            try MessageRecord
                .filter(Column("requestId") == requestId)
                .fetchOne(db)
        }
    }

    public func finalizeInterruptedMessages() throws {
        try dbManager.write { db in
            // Find all messages in streaming state (not yet terminal)
            let streamingMessages = try MessageRecord
                .filter(Column("status") == MessageStatus.streaming.rawValue)
                .fetchAll(db)

            for var message in streamingMessages {
                message.status = .interrupted
                message.updatedAt = .now
                message.syncState = .pending
                try message.update(db)

                let outbox = SyncOutboxRecord(
                    entityType: "message",
                    entityId: message.id,
                    operationType: .update
                )
                try outbox.insert(db)
            }
        }
    }

    public func softDeleteMessages(conversationId: String) throws {
        try dbManager.write { db in
            let now = Date.now
            try db.execute(
                sql: """
                UPDATE messages
                SET deletedAt = ?, updatedAt = ?, syncState = ?
                WHERE conversationId = ? AND deletedAt IS NULL
                """,
                arguments: [now, now, SyncState.pending.rawValue, conversationId]
            )
        }
    }
}
