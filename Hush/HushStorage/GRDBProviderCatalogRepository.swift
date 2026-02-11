import Foundation
import GRDB

// MARK: - GRDB Provider Catalog Repository

/// GRDB-backed implementation of `ProviderCatalogRepository`.
/// Provides provider-scoped upsert/query of model catalog data and refresh state.
public final class GRDBProviderCatalogRepository: ProviderCatalogRepository, Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Query

    public func models(forProviderID providerID: String) throws -> [ModelDescriptor] {
        let records: [ProviderCatalogModelRecord] = try dbManager.read { db in
            try ProviderCatalogModelRecord
                .filter(Column("providerID") == providerID)
                .order(Column("displayName").asc, Column("modelID").asc)
                .fetchAll(db)
        }
        return records.map { $0.toModelDescriptor() }
    }

    // MARK: - Upsert

    public func upsertCatalog(
        providerID: String,
        models: [ModelDescriptor]
    ) throws {
        let now = Date.now

        try dbManager.write { db in
            // Ensure snapshot row exists (upsert)
            let snapshot = ProviderCatalogSnapshotRecord(
                providerID: providerID,
                fetchedAt: now,
                status: CatalogSnapshotStatus.success.rawValue,
                lastError: nil
            )
            try snapshot.save(db, onConflict: .replace)

            // Delete existing models for this provider, then insert fresh set
            try ProviderCatalogModelRecord
                .filter(Column("providerID") == providerID)
                .deleteAll(db)

            for descriptor in models {
                let record = ProviderCatalogModelRecord.from(
                    descriptor: descriptor,
                    providerID: providerID,
                    updatedAt: now
                )
                try record.insert(db)
            }
        }
    }

    // MARK: - Refresh Failure

    public func recordRefreshFailure(
        providerID: String,
        error: String
    ) throws {
        try dbManager.write { db in
            // Check if snapshot exists
            if var existing = try ProviderCatalogSnapshotRecord.fetchOne(
                db,
                key: providerID
            ) {
                existing.status = CatalogSnapshotStatus.error.rawValue
                existing.lastError = error
                try existing.update(db)
            } else {
                // Create initial snapshot with error status
                let snapshot = ProviderCatalogSnapshotRecord(
                    providerID: providerID,
                    fetchedAt: nil,
                    status: CatalogSnapshotStatus.error.rawValue,
                    lastError: error
                )
                try snapshot.insert(db)
            }
        }
    }

    // MARK: - Refresh Status

    public func refreshStatus(forProviderID providerID: String) throws -> ProviderCatalogRefreshStatus {
        try dbManager.read { db in
            let snapshot = try ProviderCatalogSnapshotRecord.fetchOne(
                db,
                key: providerID
            )

            let modelCount = try ProviderCatalogModelRecord
                .filter(Column("providerID") == providerID)
                .fetchCount(db)

            return ProviderCatalogRefreshStatus(
                providerID: providerID,
                lastSuccessAt: snapshot?.fetchedAt,
                lastError: snapshot?.lastError,
                modelCount: modelCount
            )
        }
    }

    // MARK: - Cleanup

    public func removeCatalog(forProviderID providerID: String) throws {
        try dbManager.write { db in
            // Models cascade-delete via foreign key, but be explicit
            try ProviderCatalogModelRecord
                .filter(Column("providerID") == providerID)
                .deleteAll(db)
            try ProviderCatalogSnapshotRecord
                .filter(Column("providerID") == providerID)
                .deleteAll(db)
        }
    }
}
