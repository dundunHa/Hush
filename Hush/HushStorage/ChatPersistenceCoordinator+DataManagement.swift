import Foundation
import GRDB
import os

extension ChatPersistenceCoordinator {
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

    nonisolated func conversationCount() throws -> Int {
        try dbManager.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM conversations WHERE deletedAt IS NULL"
            ) ?? 0
        }
    }

    nonisolated func messageCount() throws -> Int {
        try dbManager.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM messages WHERE deletedAt IS NULL"
            ) ?? 0
        }
    }

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

    public func pendingOutboxEntries(limit: Int = 50) throws -> [SyncOutboxRecord] {
        try outboxRepo.fetchPending(limit: limit)
    }
}
