import Foundation
import GRDB

// MARK: - GRDB App Preferences Repository

/// GRDB-backed repository for app preferences stored in SQLite.
/// Manages a single "default" preferences row as a singleton-style store.
public final class GRDBAppPreferencesRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Query

    public func fetch() throws -> AppPreferencesRecord? {
        try dbManager.read { db in
            try AppPreferencesRecord.fetchOne(db)
        }
    }

    // MARK: - Save

    public func save(_ settings: AppSettings) throws {
        try dbManager.write { db in
            let record = AppPreferencesRecord.from(settings)
            try record.save(db, onConflict: .replace)
        }
    }
}
