import Foundation
import GRDB

public final class GRDBPromptTemplateRepository: PromptTemplateRepository, Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Query

    public func fetchAll() throws -> [PromptTemplate] {
        let records: [PromptTemplateRecord] = try dbManager.read { db in
            try PromptTemplateRecord
                .order(Column("name").asc, Column("id").asc)
                .fetchAll(db)
        }
        return records.map { $0.toPromptTemplate() }
    }

    public func fetch(id: String) throws -> PromptTemplate? {
        let record: PromptTemplateRecord? = try dbManager.read { db in
            try PromptTemplateRecord.fetchOne(db, key: id)
        }
        return record?.toPromptTemplate()
    }

    // MARK: - Upsert

    public func upsert(_ template: PromptTemplate) throws {
        try dbManager.write { db in
            let existing = try PromptTemplateRecord.fetchOne(db, key: template.id)
            let now = Date.now
            let record = PromptTemplateRecord.from(
                template,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            try record.save(db, onConflict: .replace)
        }
    }

    // MARK: - Delete

    public func delete(id: String) throws {
        try dbManager.write { db in
            try PromptTemplateRecord
                .filter(Column("id") == id)
                .deleteAll(db)
        }
    }
}
