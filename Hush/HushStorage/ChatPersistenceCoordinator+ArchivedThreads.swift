import Foundation
import GRDB

extension ChatPersistenceCoordinator {
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
}
