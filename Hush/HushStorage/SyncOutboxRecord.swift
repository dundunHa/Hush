import Foundation
import GRDB

// MARK: - Outbox Operation Type

public nonisolated enum OutboxOperationType: String, Codable, Sendable {
    case insert
    case update
    case delete
}

// MARK: - Outbox Status

public nonisolated enum OutboxStatus: String, Codable, Sendable {
    case pending
    case dispatched
    case failed
}

// MARK: - Sync Outbox Record

/// GRDB-backed record for the `syncOutbox` table.
/// Captures local mutations for future sync worker consumption.
public nonisolated struct SyncOutboxRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var entityType: String // "conversation" | "message"
    public var entityId: String
    public var operationType: OutboxOperationType
    public var status: OutboxStatus
    public var retryCount: Int
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        entityType: String,
        entityId: String,
        operationType: OutboxOperationType,
        status: OutboxStatus = .pending,
        retryCount: Int = 0,
        lastError: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.operationType = operationType
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Conformances

nonisolated extension SyncOutboxRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "syncOutbox"
}
