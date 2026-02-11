import Foundation
import GRDB

// MARK: - GRDB Sync Outbox Repository

/// GRDB-backed implementation of `SyncOutboxRepository`.
public final class GRDBSyncOutboxRepository: SyncOutboxRepository, Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public func append(_ entry: SyncOutboxRecord) throws {
        try dbManager.write { db in
            try entry.insert(db)
        }
    }

    public func fetchPending(limit: Int = 50) throws -> [SyncOutboxRecord] {
        try dbManager.read { db in
            try SyncOutboxRecord
                .filter(Column("status") == OutboxStatus.pending.rawValue)
                .order(Column("createdAt").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func markDispatched(id: Int64) throws {
        try dbManager.write { db in
            try db.execute(
                sql: """
                UPDATE syncOutbox
                SET status = ?, updatedAt = ?
                WHERE id = ?
                """,
                arguments: [OutboxStatus.dispatched.rawValue, Date.now, id]
            )
        }
    }

    public func markFailed(id: Int64, error: String) throws {
        try dbManager.write { db in
            try db.execute(
                sql: """
                UPDATE syncOutbox
                SET status = ?, lastError = ?, retryCount = retryCount + 1, updatedAt = ?
                WHERE id = ?
                """,
                arguments: [OutboxStatus.failed.rawValue, error, Date.now, id]
            )
        }
    }
}
