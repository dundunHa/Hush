import Foundation
import GRDB

// MARK: - GRDB Agent Preset Repository

/// GRDB-backed implementation of `AgentPresetRepository`.
/// Provides CRUD operations for agent presets stored in SQLite.
public final class GRDBAgentPresetRepository: AgentPresetRepository, Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Query

    public func fetchAll() throws -> [AgentPreset] {
        let records: [AgentPresetRecord] = try dbManager.read { db in
            try AgentPresetRecord
                .order(Column("name").asc, Column("id").asc)
                .fetchAll(db)
        }
        return records.map { $0.toAgentPreset() }
    }

    public func fetch(id: String) throws -> AgentPreset? {
        let record: AgentPresetRecord? = try dbManager.read { db in
            try AgentPresetRecord.fetchOne(db, key: id)
        }
        return record?.toAgentPreset()
    }

    // MARK: - Upsert

    public func upsert(_ preset: AgentPreset) throws {
        try dbManager.write { db in
            let existing = try AgentPresetRecord.fetchOne(db, key: preset.id)
            let now = Date.now
            let record = AgentPresetRecord.from(
                preset,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            try record.save(db, onConflict: .replace)
        }
    }

    // MARK: - Delete

    public func delete(id: String) throws {
        try dbManager.write { db in
            try AgentPresetRecord
                .filter(Column("id") == id)
                .deleteAll(db)
        }
    }
}
