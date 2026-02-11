import Foundation
import GRDB
@testable import Hush
import Testing

// MARK: - 6.3 Sync Metadata and Outbox Tests

@Suite("Sync Outbox Tests")
struct SyncOutboxTests {
    private func makeRepo() throws -> (GRDBSyncOutboxRepository, DatabaseManager) {
        let db = try DatabaseManager.inMemory()
        return (GRDBSyncOutboxRepository(dbManager: db), db)
    }

    @Test("Append and fetch pending entries")
    func appendAndFetchPending() throws {
        let (repo, _) = try makeRepo()

        let entry = SyncOutboxRecord(
            entityType: "message",
            entityId: UUID().uuidString,
            operationType: .insert
        )
        try repo.append(entry)

        let pending = try repo.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].entityType == "message")
        #expect(pending[0].operationType == .insert)
        #expect(pending[0].status == .pending)
    }

    @Test("Fetch pending returns deterministic order (ascending createdAt)")
    func fetchPendingDeterministicOrder() throws {
        let (repo, _) = try makeRepo()

        let entry1 = SyncOutboxRecord(
            entityType: "conversation",
            entityId: "c1",
            operationType: .insert,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        let entry2 = SyncOutboxRecord(
            entityType: "message",
            entityId: "m1",
            operationType: .insert,
            createdAt: Date(timeIntervalSince1970: 2000)
        )

        try repo.append(entry1)
        try repo.append(entry2)

        let pending = try repo.fetchPending(limit: 10)
        #expect(pending.count == 2)
        #expect(pending[0].entityId == "c1")
        #expect(pending[1].entityId == "m1")
    }

    @Test("Mark dispatched excludes from pending")
    func markDispatchedExcludes() throws {
        let (repo, _) = try makeRepo()

        let entry = SyncOutboxRecord(
            entityType: "message",
            entityId: "m1",
            operationType: .update
        )
        try repo.append(entry)

        let pending = try repo.fetchPending(limit: 10)
        guard let id = pending.first?.id else {
            #expect(Bool(false), "Expected pending entry")
            return
        }

        try repo.markDispatched(id: id)

        let pendingAfter = try repo.fetchPending(limit: 10)
        #expect(pendingAfter.isEmpty)
    }

    @Test("Mark failed increments retry count")
    func markFailedIncrementsRetry() throws {
        let (repo, db) = try makeRepo()

        let entry = SyncOutboxRecord(
            entityType: "message",
            entityId: "m1",
            operationType: .insert
        )
        try repo.append(entry)

        let pending = try repo.fetchPending(limit: 10)
        guard let id = pending.first?.id else {
            #expect(Bool(false), "Expected pending entry")
            return
        }

        try repo.markFailed(id: id, error: "Network timeout")

        let row = try db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM syncOutbox WHERE id = ?", arguments: [id])
        }
        #expect(row?["retryCount"] as Int? == 1)
        #expect(row?["lastError"] as String? == "Network timeout")
        #expect(row?["status"] as String? == "failed")
    }

    @Test("Pending entries survive across database re-open")
    func pendingEntriesSurviveRestart() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let path = tmpDir.appendingPathComponent("outbox_test.sqlite").path

        // Session 1: create an entry
        let db1 = try DatabaseManager(path: path)
        let repo1 = GRDBSyncOutboxRepository(dbManager: db1)
        let entry = SyncOutboxRecord(
            entityType: "conversation",
            entityId: "c1",
            operationType: .insert
        )
        try repo1.append(entry)

        // Session 2: re-open, entry should still be there
        let db2 = try DatabaseManager(path: path)
        let repo2 = GRDBSyncOutboxRepository(dbManager: db2)
        let pending = try repo2.fetchPending(limit: 10)
        #expect(pending.count == 1)
        #expect(pending[0].entityId == "c1")
    }

    @Test("Mutation with sync metadata creates outbox entry atomically")
    func mutationCreatesOutboxAtomically() throws {
        let db = try DatabaseManager.inMemory()
        let convRepo = GRDBConversationRepository(dbManager: db)
        let outboxRepo = GRDBSyncOutboxRepository(dbManager: db)

        let conv = ConversationRecord(title: "Atomic test")
        try convRepo.create(conv)

        // Verify: conversation created AND outbox entry exists
        let pending = try outboxRepo.fetchPending(limit: 10)
        let convOutbox = pending.filter { $0.entityType == "conversation" && $0.entityId == conv.id }
        #expect(convOutbox.count == 1)
        #expect(convOutbox[0].operationType == .insert)
    }

    @Test("Failed mutation appends no outbox record")
    func failedMutationAppendsNoOutbox() throws {
        let db = try DatabaseManager.inMemory()
        let convRepo = GRDBConversationRepository(dbManager: db)

        let fixedID = UUID().uuidString
        let first = ConversationRecord(id: fixedID, title: "first")
        try convRepo.create(first)

        let duplicate = ConversationRecord(id: fixedID, title: "duplicate")
        do {
            try convRepo.create(duplicate)
            #expect(Bool(false), "Expected duplicate primary-key insert to fail")
        } catch {
            // expected: failed mutation must not append extra outbox rows
        }

        let counts = try db.read { db in
            let conversationCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM conversations WHERE id = ?",
                arguments: [fixedID]
            ) ?? 0
            let outboxCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM syncOutbox WHERE entityType = ? AND entityId = ?",
                arguments: ["conversation", fixedID]
            ) ?? 0
            return (conversationCount, outboxCount)
        }

        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
    }
}
