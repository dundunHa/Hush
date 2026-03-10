import Foundation
import GRDB
@testable import Hush
import Testing

// MARK: - 2.4 Migration Tests

/// Verifies idempotent startup and expected schema versioning behavior.
struct DatabaseMigrationTests {
    @Test("Database opens and migrates successfully")
    func databaseOpensAndMigrates() throws {
        let db = try DatabaseManager.inMemory()
        // Verify tables exist by querying them
        let conversationCount = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM conversations")
        }
        #expect(conversationCount == 0)
    }

    @Test("Idempotent startup: opening twice does not error")
    func idempotentStartup() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let path = tmpDir.appendingPathComponent("test.sqlite").path

        _ = try DatabaseManager(path: path)
        // Opening same path a second time should succeed (idempotent migrations)
        _ = try DatabaseManager(path: path)
    }

    @Test("Conversations table has expected columns")
    func conversationsTableSchema() throws {
        let db = try DatabaseManager.inMemory()
        let columns = try db.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(conversations)")
        }
        let columnNames = columns.map { $0["name"] as String }
        #expect(columnNames.contains("id"))
        #expect(columnNames.contains("title"))
        #expect(columnNames.contains("createdAt"))
        #expect(columnNames.contains("updatedAt"))
        #expect(columnNames.contains("deletedAt"))
        #expect(columnNames.contains("syncState"))
        #expect(columnNames.contains("sourceDeviceId"))
    }

    @Test("Messages table has expected columns")
    func messagesTableSchema() throws {
        let db = try DatabaseManager.inMemory()
        let columns = try db.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(messages)")
        }
        let columnNames = columns.map { $0["name"] as String }
        #expect(columnNames.contains("id"))
        #expect(columnNames.contains("conversationId"))
        #expect(columnNames.contains("role"))
        #expect(columnNames.contains("content"))
        #expect(columnNames.contains("status"))
        #expect(columnNames.contains("requestId"))
        #expect(columnNames.contains("orderIndex"))
        #expect(columnNames.contains("createdAt"))
        #expect(columnNames.contains("updatedAt"))
        #expect(columnNames.contains("deletedAt"))
        #expect(columnNames.contains("syncState"))
        #expect(columnNames.contains("sourceDeviceId"))
    }

    @Test("Sync outbox table has expected columns")
    func syncOutboxTableSchema() throws {
        let db = try DatabaseManager.inMemory()
        let columns = try db.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(syncOutbox)")
        }
        let columnNames = columns.map { $0["name"] as String }
        #expect(columnNames.contains("id"))
        #expect(columnNames.contains("entityType"))
        #expect(columnNames.contains("entityId"))
        #expect(columnNames.contains("operationType"))
        #expect(columnNames.contains("status"))
        #expect(columnNames.contains("retryCount"))
        #expect(columnNames.contains("lastError"))
        #expect(columnNames.contains("createdAt"))
        #expect(columnNames.contains("updatedAt"))
    }

    @Test("Messages table has expected indexes")
    func messagesIndexes() throws {
        let db = try DatabaseManager.inMemory()
        let indexes = try db.read { db in
            try Row.fetchAll(db, sql: "PRAGMA index_list(messages)")
        }
        let indexNames = indexes.map { $0["name"] as String }
        #expect(indexNames.contains("idx_messages_conversationId_orderIndex"))
        #expect(indexNames.contains("idx_messages_requestId"))
        #expect(indexNames.contains("idx_messages_syncState"))
    }

    @Test("appPreferences table includes maxConcurrentRequests column after v8 migration")
    func appPreferencesConcurrencyColumn() throws {
        let db = try DatabaseManager.inMemory()
        let columns = try db.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(appPreferences)")
        }
        let columnNames = columns.map { $0["name"] as String }
        #expect(columnNames.contains("maxConcurrentRequests"))
    }

    @Test("appPreferences table includes reasoningEffort column after v11 migration")
    func appPreferencesReasoningEffortColumn() throws {
        let db = try DatabaseManager.inMemory()
        let columns = try db.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(appPreferences)")
        }
        let columnNames = columns.map { $0["name"] as String }
        #expect(columnNames.contains("reasoningEffort"))
    }
}
