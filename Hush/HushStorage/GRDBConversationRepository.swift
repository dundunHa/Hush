import Foundation
import GRDB

// MARK: - GRDB Conversation Repository

/// GRDB-backed implementation of `ConversationRepository`.
public final class GRDBConversationRepository: ConversationRepository, Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public func fetchMostRecent() throws -> ConversationRecord? {
        try dbManager.read { db in
            try ConversationRecord
                .filter(Column("deletedAt") == nil)
                .order(Column("updatedAt").desc)
                .fetchOne(db)
        }
    }

    public func create(_ conversation: ConversationRecord) throws {
        try dbManager.write { db in
            try conversation.insert(db)

            // Append outbox entry in same transaction
            let outbox = SyncOutboxRecord(
                entityType: "conversation",
                entityId: conversation.id,
                operationType: .insert
            )
            try outbox.insert(db)
        }
    }

    public func softDelete(id: String) throws {
        try dbManager.write { db in
            let now = Date.now
            try db.execute(
                sql: """
                UPDATE conversations
                SET deletedAt = ?, updatedAt = ?, syncState = ?
                WHERE id = ?
                """,
                arguments: [now, now, SyncState.pending.rawValue, id]
            )

            // Append outbox entry in same transaction
            let outbox = SyncOutboxRecord(
                entityType: "conversation",
                entityId: id,
                operationType: .delete
            )
            try outbox.insert(db)
        }
    }

    public func setArchived(id: String, isArchived: Bool) throws {
        try dbManager.write { db in
            try db.execute(
                sql: """
                UPDATE conversations
                SET isArchived = ?, updatedAt = ?
                WHERE id = ?
                """,
                arguments: [isArchived, Date.now, id]
            )
        }
    }
}
