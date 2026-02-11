import Foundation
import GRDB

// MARK: - GRDB Provider Configuration Repository

/// GRDB-backed implementation of `ProviderConfigurationRepository`.
/// Provides CRUD operations for provider configurations stored in SQLite.
public final class GRDBProviderConfigurationRepository: ProviderConfigurationRepository, Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Query

    public func fetchAll() throws -> [ProviderConfiguration] {
        let records: [ProviderConfigurationRecord] = try dbManager.read { db in
            try ProviderConfigurationRecord
                .order(Column("name").asc, Column("id").asc)
                .fetchAll(db)
        }
        return records.map { $0.toProviderConfiguration() }
    }

    public func fetch(id: String) throws -> ProviderConfiguration? {
        let record: ProviderConfigurationRecord? = try dbManager.read { db in
            try ProviderConfigurationRecord.fetchOne(db, key: id)
        }
        return record?.toProviderConfiguration()
    }

    // MARK: - Upsert

    public func upsert(_ config: ProviderConfiguration) throws {
        try dbManager.write { db in
            let existing = try ProviderConfigurationRecord.fetchOne(db, key: config.id)
            let now = Date.now
            let record = ProviderConfigurationRecord.from(
                config,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            try record.save(db, onConflict: .replace)
        }
    }

    // MARK: - Delete

    public func delete(id: String) throws {
        try dbManager.write { db in
            try ProviderConfigurationRecord
                .filter(Column("id") == id)
                .deleteAll(db)
        }
    }
}
