import Foundation
import GRDB

// MARK: - Database Manager

/// Bootstraps and manages the SQLite database lifecycle via GRDB.
/// Opens the database in Application Support/Hush, runs migrations,
/// and provides thread-safe, lifecycle-safe access through a `DatabasePool`.
public final class DatabaseManager: Sendable {
    /// The underlying GRDB database pool for concurrent reads.
    public let pool: DatabasePool

    /// The filesystem path of the SQLite database file.
    public let databasePath: String

    // MARK: - Init

    /// Opens (or creates) the database at the given path and runs all migrations.
    ///
    /// - Parameter path: Full filesystem path for the SQLite file.
    /// - Throws: Any GRDB or filesystem error during open/migrate.
    public init(path: String) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // Enable WAL mode for concurrent reads during writes.
            // GRDB recommends this for app targets.
            db.trace { /* no-op in production; can be wired to os_log */ _ in }
        }

        pool = try DatabasePool(path: path, configuration: configuration)
        databasePath = path
        try migrator.migrate(pool)
    }

    // MARK: - Migrations

    /// The single, forward-only migrator that defines every schema version.
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Wipe database on schema change during development only.
        #if DEBUG
            migrator.eraseDatabaseOnSchemaChange = true
        #endif

        // ── v1: conversations + messages ────────────────────────────────
        migrator.registerMigration("v1_conversations_messages") { db in
            try db.create(table: "conversations") { t in
                t.primaryKey("id", .text).notNull()
                t.column("title", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
                t.column("syncState", .text).notNull().defaults(to: "pending")
                t.column("sourceDeviceId", .text).notNull()
            }

            try db.create(table: "messages") { t in
                t.primaryKey("id", .text).notNull()
                t.column("conversationId", .text).notNull()
                    .references("conversations", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "final")
                t.column("requestId", .text)
                t.column("orderIndex", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
                t.column("syncState", .text).notNull().defaults(to: "pending")
                t.column("sourceDeviceId", .text).notNull()
            }

            // Indexes for message queries
            try db.create(
                index: "idx_messages_conversationId_orderIndex",
                on: "messages",
                columns: ["conversationId", "orderIndex"]
            )
            try db.create(
                index: "idx_messages_requestId",
                on: "messages",
                columns: ["requestId"]
            )
            try db.create(
                index: "idx_messages_syncState",
                on: "messages",
                columns: ["syncState"]
            )
            try db.create(
                index: "idx_conversations_syncState",
                on: "conversations",
                columns: ["syncState"]
            )
            try db.create(
                index: "idx_conversations_updatedAt",
                on: "conversations",
                columns: ["updatedAt"]
            )
        }

        // ── v2: sync_outbox ─────────────────────────────────────────────
        migrator.registerMigration("v2_sync_outbox") { db in
            try db.create(table: "syncOutbox") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entityType", .text).notNull() // "conversation" | "message"
                t.column("entityId", .text).notNull()
                t.column("operationType", .text).notNull() // "insert" | "update" | "delete"
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("retryCount", .integer).notNull().defaults(to: 0)
                t.column("lastError", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_syncOutbox_status_createdAt",
                on: "syncOutbox",
                columns: ["status", "createdAt"]
            )
        }

        // ── v3: provider catalog cache ──────────────────────────────────
        migrator.registerMigration("v3_provider_catalog_cache") { db in
            // Snapshot-level refresh state per provider
            try db.create(table: "providerCatalogSnapshots") { t in
                t.primaryKey("providerID", .text).notNull()
                t.column("fetchedAt", .datetime)
                t.column("status", .text).notNull().defaults(to: "empty")
                t.column("lastError", .text)
            }

            // Individual model records scoped to a provider
            try db.create(table: "providerCatalogModels") { t in
                t.column("providerID", .text).notNull()
                t.column("modelID", .text).notNull()
                t.column("displayName", .text).notNull()
                t.column("modelType", .text).notNull().defaults(to: "unknown")
                t.column("supportedInputs", .text).notNull().defaults(to: "[\"text\"]")
                t.column("supportedOutputs", .text).notNull().defaults(to: "[\"text\"]")
                t.column("limitsJSON", .text)
                t.column("rawMetadataJSON", .text)
                t.column("updatedAt", .datetime).notNull()

                // Composite primary key: (providerID, modelID)
                t.primaryKey(["providerID", "modelID"])

                t.foreignKey(
                    ["providerID"],
                    references: "providerCatalogSnapshots",
                    columns: ["providerID"],
                    onDelete: .cascade
                )
            }

            // Index for deterministic ordering within a provider
            try db.create(
                index: "idx_providerCatalogModels_providerID_displayName",
                on: "providerCatalogModels",
                columns: ["providerID", "displayName"]
            )
        }

        // ── v4: provider configurations ─────────────────────────────────
        migrator.registerMigration("v4_provider_configurations") { db in
            try db.create(table: "providerConfigurations") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("endpoint", .text).notNull()
                t.column("apiKeyEnvironmentVariable", .text).notNull().defaults(to: "")
                t.column("defaultModelID", .text).notNull().defaults(to: "")
                t.column("isEnabled", .boolean).notNull().defaults(to: false)
                t.column("credentialRef", .text)
                t.column("pinnedModelIDs", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        // ── v5: app preferences ─────────────────────────────────────────
        migrator.registerMigration("v5_app_preferences") { db in
            try db.create(table: "appPreferences") { t in
                t.primaryKey("id", .text).notNull()
                t.column("selectedProviderID", .text).notNull()
                t.column("selectedModelID", .text).notNull()
                t.column("temperature", .double).notNull()
                t.column("topP", .double).notNull()
                t.column("topK", .integer)
                t.column("maxTokens", .integer).notNull()
                t.column("presencePenalty", .double).notNull()
                t.column("frequencyPenalty", .double).notNull()
                t.column("contextMessageLimit", .integer)
                t.column("quickBarKey", .text).notNull()
                t.column("quickBarModifiers", .text).notNull().defaults(to: "[]")
                t.column("theme", .text).notNull().defaults(to: "dark")
                t.column("updatedAt", .datetime).notNull()
            }
        }

        // ── v6: agent presets ───────────────────────────────────────────
        migrator.registerMigration("v6_agent_presets") { db in
            try db.create(table: "agentPresets") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("systemPrompt", .text).notNull().defaults(to: "")
                t.column("providerID", .text).notNull().defaults(to: "")
                t.column("modelID", .text).notNull().defaults(to: "")
                t.column("temperature", .double).notNull().defaults(to: 0.7)
                t.column("topP", .double).notNull().defaults(to: 1.0)
                t.column("topK", .integer)
                t.column("maxTokens", .integer).notNull().defaults(to: 4096)
                t.column("thinkingBudget", .integer)
                t.column("presencePenalty", .double).notNull().defaults(to: 0.0)
                t.column("frequencyPenalty", .double).notNull().defaults(to: 0.0)
                t.column("isDefault", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_agentPresets_name",
                on: "agentPresets",
                columns: ["name"]
            )
        }

        // ── v7: prompt templates ────────────────────────────────────────
        migrator.registerMigration("v7_prompt_templates") { db in
            try db.create(table: "promptTemplates") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("category", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_promptTemplates_name",
                on: "promptTemplates",
                columns: ["name"]
            )
        }

        // ── v8: add maxConcurrentRequests to appPreferences ───────────
        migrator.registerMigration("v8_app_preferences_concurrency") { db in
            try db.alter(table: "appPreferences") { t in
                t.add(column: "maxConcurrentRequests", .integer)
            }
        }

        // ── v9: add isArchived to conversations ────────────────────────
        migrator.registerMigration("v9_conversations_archive") { db in
            try db.alter(table: "conversations") { t in
                t.add(column: "isArchived", .boolean).notNull().defaults(to: false)
            }
        }

        // ── v10: add useModelDefaults to appPreferences ───────────────
        migrator.registerMigration("v10_app_preferences_use_model_defaults") { db in
            try db.alter(table: "appPreferences") { t in
                t.add(column: "useModelDefaults", .boolean).notNull().defaults(to: false)
            }
        }

        // ── v11: add reasoningEffort to appPreferences ───────────────
        migrator.registerMigration("v11_app_preferences_reasoning_effort") { db in
            try db.alter(table: "appPreferences") { t in
                t.add(column: "reasoningEffort", .text)
            }
        }

        // ── v12: add shared typography settings to appPreferences ────
        migrator.registerMigration("v12_app_preferences_typography") { db in
            try db.alter(table: "appPreferences") { t in
                t.add(column: "fontFamilyName", .text)
                t.add(column: "fontSize", .double)
            }
        }

        // ── v13: persist provider API keys in SQLite ───────────────────
        migrator.registerMigration("v13_provider_configuration_api_keys") { db in
            try db.alter(table: "providerConfigurations") { t in
                t.add(column: "apiKey", .text).notNull().defaults(to: "")
            }
        }

        return migrator
    }

    // MARK: - Convenience

    /// Read-only access to the database.
    public nonisolated func read<T>(_ block: (Database) throws -> T) throws -> T {
        try pool.read(block)
    }

    /// Read-write access to the database.
    public nonisolated func write<T>(_ block: (Database) throws -> T) throws -> T {
        try pool.write(block)
    }

    /// Reclaims disk space by rebuilding the database file.
    public nonisolated func vacuum() throws {
        try pool.barrierWriteWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            try db.execute(sql: "VACUUM")
        }
    }

    // MARK: - Bootstrap

    /// Creates a `DatabaseManager` at the default Application Support location.
    public static func appDefault() throws -> DatabaseManager {
        let baseURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Hush", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Hush", isDirectory: true)

        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )

        let dbPath = baseURL.appendingPathComponent("hush.sqlite").path
        return try DatabaseManager(path: dbPath)
    }

    /// Creates an in-memory `DatabaseManager` for testing.
    public static func inMemory() throws -> DatabaseManager {
        // Use a temporary file so DatabasePool works (it requires a file).
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let path = tmpDir.appendingPathComponent("test.sqlite").path
        return try DatabaseManager(path: path)
    }
}
