import Foundation
import GRDB

// MARK: - Conversation Record

/// GRDB-backed record for the `conversations` table.
public nonisolated struct ConversationRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var syncState: SyncState
    public var sourceDeviceId: String
    public var isArchived: Bool

    public init(
        id: String = UUID().uuidString,
        title: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        syncState: SyncState = .pending,
        sourceDeviceId: String = DeviceIdentifier.current,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncState = syncState
        self.sourceDeviceId = sourceDeviceId
        self.isArchived = isArchived
    }
}

// MARK: - GRDB Conformances

nonisolated extension ConversationRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "conversations"
}
