import Foundation
import GRDB

// MARK: - Message Status

/// Tracks the lifecycle state of a persisted message.
public nonisolated enum MessageStatus: String, Codable, Sendable {
    /// User message or finalized assistant message.
    case final_ = "final"
    /// Assistant message currently being streamed.
    case streaming
    /// Terminal: request completed normally.
    case completed
    /// Terminal: request failed with an error.
    case failed
    /// Terminal: request was stopped by user.
    case stopped
    /// Terminal: app exited before terminal state was recorded.
    case interrupted
}

// MARK: - Message Record

/// GRDB-backed record for the `messages` table.
public nonisolated struct MessageRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var conversationId: String
    public var role: String // "user" | "assistant" | "system" | "tool"
    public var content: String
    public var status: MessageStatus
    public var requestId: String?
    public var orderIndex: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var syncState: SyncState
    public var sourceDeviceId: String

    public init(
        id: String = UUID().uuidString,
        conversationId: String,
        role: String,
        content: String,
        status: MessageStatus = .final_,
        requestId: String? = nil,
        orderIndex: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        syncState: SyncState = .pending,
        sourceDeviceId: String = DeviceIdentifier.current
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.status = status
        self.requestId = requestId
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncState = syncState
        self.sourceDeviceId = sourceDeviceId
    }
}

// MARK: - GRDB Conformances

nonisolated extension MessageRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "messages"
}
