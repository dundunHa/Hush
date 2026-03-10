import Foundation

// MARK: - Conversation Repository

/// Defines data access operations for conversations.
public protocol ConversationRepository: Sendable {
    /// Returns the most recently updated conversation, or nil if none exist.
    func fetchMostRecent() throws -> ConversationRecord?

    /// Creates a new conversation and persists it.
    func create(_ conversation: ConversationRecord) throws

    /// Soft-deletes a conversation (sets `deletedAt`).
    func softDelete(id: String) throws

    /// Sets the archive state for a conversation.
    func setArchived(id: String, isArchived: Bool) throws
}

// MARK: - Message Repository

public nonisolated struct MessageRecordPage: Sendable, Equatable {
    public let records: [MessageRecord]
    public let hasMoreOlder: Bool
    public let oldestOrderIndex: Int?
    public let newestOrderIndex: Int?

    public init(
        records: [MessageRecord],
        hasMoreOlder: Bool,
        oldestOrderIndex: Int?,
        newestOrderIndex: Int?
    ) {
        self.records = records
        self.hasMoreOlder = hasMoreOlder
        self.oldestOrderIndex = oldestOrderIndex
        self.newestOrderIndex = newestOrderIndex
    }
}

/// Defines data access operations for messages within a conversation.
public protocol MessageRepository: Sendable {
    /// Returns non-deleted messages for a conversation, ordered by `orderIndex`.
    /// - Parameters:
    ///   - conversationId: The conversation to fetch messages for.
    ///   - limit: Optional maximum number of messages to return.
    func fetchMessages(conversationId: String, limit: Int?) throws -> [MessageRecord]

    /// Returns a chronological page of non-deleted messages for a conversation.
    ///
    /// - Parameters:
    ///   - conversationId: The conversation to fetch messages for.
    ///   - beforeOrderIndex: When provided, fetches messages with `orderIndex` less than this value.
    ///   - limit: Page size.
    func fetchMessagesPage(conversationId: String, beforeOrderIndex: Int?, limit: Int) throws -> MessageRecordPage

    /// Returns the next `orderIndex` for a conversation.
    func nextOrderIndex(conversationId: String) throws -> Int

    /// Inserts a new message record.
    func insert(_ message: MessageRecord) throws

    /// Updates an existing message record (content, status, etc.).
    func update(_ message: MessageRecord) throws

    /// Finds a message by its request ID (for correlating streaming updates).
    func fetchByRequestId(_ requestId: String) throws -> MessageRecord?

    /// Finalizes all in-progress (streaming) messages as interrupted.
    /// Called during crash recovery on app launch.
    func finalizeInterruptedMessages() throws

    /// Soft-deletes all messages belonging to a conversation (sets `deletedAt`).
    func softDeleteMessages(conversationId: String) throws
}

// MARK: - Sync Outbox Repository

/// Defines data access operations for the sync outbox.
public protocol SyncOutboxRepository: Sendable {
    /// Appends a new outbox entry.
    func append(_ entry: SyncOutboxRecord) throws

    /// Returns pending entries ordered by creation time (ascending).
    func fetchPending(limit: Int) throws -> [SyncOutboxRecord]

    /// Marks an entry as dispatched.
    func markDispatched(id: Int64) throws

    /// Marks an entry as failed with an error message and increments retry count.
    func markFailed(id: Int64, error: String) throws
}

// MARK: - Credential Reference Repository

/// Legacy data access for credential references kept for compatibility with older stored data.
public protocol CredentialReferenceRepository: Sendable {
    /// Returns the legacy credential reference for a provider.
    func credentialRef(forProviderID providerID: String) -> String?

    /// Stores or updates a credential reference for a provider.
    func setCredentialRef(_ ref: String, forProviderID providerID: String)

    /// Removes the credential reference for a provider.
    func removeCredentialRef(forProviderID providerID: String)
}

// MARK: - Provider Configuration Repository

/// Defines data access for provider configuration records stored in SQLite.
public protocol ProviderConfigurationRepository: Sendable {
    /// Returns all provider configurations ordered by name.
    func fetchAll() throws -> [ProviderConfiguration]

    /// Returns a single provider configuration by ID, or nil if not found.
    func fetch(id: String) throws -> ProviderConfiguration?

    /// Inserts or updates a provider configuration (upsert by primary key).
    func upsert(_ config: ProviderConfiguration) throws

    /// Deletes a provider configuration by ID.
    func delete(id: String) throws
}

// MARK: - Agent Preset Repository

/// Defines data access for agent preset templates stored in SQLite.
public protocol AgentPresetRepository: Sendable {
    /// Returns all agent presets ordered by name.
    func fetchAll() throws -> [AgentPreset]

    /// Returns a single agent preset by ID, or nil if not found.
    func fetch(id: String) throws -> AgentPreset?

    /// Inserts or updates an agent preset (upsert by primary key).
    func upsert(_ preset: AgentPreset) throws

    /// Deletes an agent preset by ID.
    func delete(id: String) throws
}

// MARK: - Prompt Template Repository

public protocol PromptTemplateRepository: Sendable {
    func fetchAll() throws -> [PromptTemplate]
    func fetch(id: String) throws -> PromptTemplate?
    func upsert(_ template: PromptTemplate) throws
    func delete(id: String) throws
}

// MARK: - Provider Catalog Repository

/// Defines data access for provider model catalog cache and refresh state.
/// All operations are provider-scoped by `providerID`.
public protocol ProviderCatalogRepository: Sendable {
    /// Returns all cached model descriptors for a provider in deterministic order.
    func models(forProviderID providerID: String) throws -> [ModelDescriptor]

    /// Replaces the entire model catalog for a provider with the given descriptors.
    /// Updates snapshot status to success with current timestamp.
    func upsertCatalog(
        providerID: String,
        models: [ModelDescriptor]
    ) throws

    /// Records a refresh failure for a provider while preserving existing catalog data.
    func recordRefreshFailure(
        providerID: String,
        error: String
    ) throws

    /// Returns the refresh status for a provider (last success time, last error, model count).
    func refreshStatus(forProviderID providerID: String) throws -> ProviderCatalogRefreshStatus

    /// Removes all catalog data for a provider (models + snapshot).
    func removeCatalog(forProviderID providerID: String) throws
}
