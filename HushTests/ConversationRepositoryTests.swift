import Foundation
import GRDB
@testable import Hush
import Testing

// MARK: - 6.1 Repository Tests: Conversations

struct ConversationRepositoryTests {
    private func makeRepo() throws -> (GRDBConversationRepository, DatabaseManager) {
        let db = try DatabaseManager.inMemory()
        let repo = GRDBConversationRepository(dbManager: db)
        return (repo, db)
    }

    @Test("Create and fetch most recent conversation")
    func createAndFetchMostRecent() throws {
        let (repo, _) = try makeRepo()

        let conv = ConversationRecord(title: "Test Conversation")
        try repo.create(conv)

        let fetched = try repo.fetchMostRecent()
        #expect(fetched != nil)
        #expect(fetched?.id == conv.id)
        #expect(fetched?.title == "Test Conversation")
    }

    @Test("Fetch most recent returns latest by updatedAt")
    func fetchMostRecentReturnsLatest() throws {
        let (repo, _) = try makeRepo()

        let old = ConversationRecord(
            title: "Old",
            createdAt: Date(timeIntervalSince1970: 1000),
            updatedAt: Date(timeIntervalSince1970: 1000)
        )
        try repo.create(old)

        let newer = ConversationRecord(
            title: "Newer",
            createdAt: Date(timeIntervalSince1970: 2000),
            updatedAt: Date(timeIntervalSince1970: 2000)
        )
        try repo.create(newer)

        let fetched = try repo.fetchMostRecent()
        #expect(fetched?.id == newer.id)
    }

    @Test("Fetch most recent returns nil for empty database")
    func fetchMostRecentEmpty() throws {
        let (repo, _) = try makeRepo()
        let fetched = try repo.fetchMostRecent()
        #expect(fetched == nil)
    }

    @Test("Soft delete excludes conversation from most recent")
    func softDeleteExcludes() throws {
        let (repo, _) = try makeRepo()

        let conv = ConversationRecord(title: "To Delete")
        try repo.create(conv)
        try repo.softDelete(id: conv.id)

        let fetched = try repo.fetchMostRecent()
        #expect(fetched == nil)
    }

    @Test("Create conversation generates outbox entry")
    func createGeneratesOutbox() throws {
        let (repo, db) = try makeRepo()

        let conv = ConversationRecord(title: "Outbox Test")
        try repo.create(conv)

        let outboxCount = try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM syncOutbox WHERE entityType = ? AND entityId = ?",
                arguments: ["conversation", conv.id]
            )
        }
        #expect(outboxCount == 1)
    }
}
