# HushStorage

GRDB-backed persistence layer with protocol-driven repositories, persisted provider credentials, file-based asset storage, and streaming coordination.

## Structure

```
StorageProtocols.swift             # All repository protocol definitions
DatabaseManager.swift              # DatabasePool setup, WAL mode, migrations v1-v8+
ChatPersistenceCoordinator.swift   # @MainActor streaming flush + finalization (611 lines)
CredentialResolver.swift           # Validates persisted provider API keys before invocation
KeychainAdapter.swift              # Legacy filename retained; no Keychain access remains
FileMessageAssetStore.swift        # File-based storage for generated images (DALL-E assets)
ConversationRecord.swift           # GRDB Record for conversations
MessageRecord.swift                # GRDB Record for messages (includes imageAssetIds)
SyncOutboxRecord.swift             # GRDB Record for sync outbox entries
SyncState.swift                    # Sync state tracking
AppPreferencesRecord.swift         # GRDB Record for app preferences
AgentPresetRecord.swift            # GRDB Record for agent presets
PromptTemplateRecord.swift         # GRDB Record for prompt templates
ProviderConfigurationRecord.swift  # GRDB Record for provider configs (includes apiKey)
ProviderCatalogRecord.swift        # GRDB Record for cached model catalogs
GRDBConversationRepository.swift   # ConversationRepository impl
GRDBMessageRepository.swift        # MessageRepository impl
GRDBSyncOutboxRepository.swift     # SyncOutboxRepository impl
GRDBCredentialRefRepository.swift  # CredentialReferenceRepository impl (legacy compat)
GRDBProviderConfigurationRepository.swift # ProviderConfigurationRepository impl
GRDBAgentPresetRepository.swift    # AgentPresetRepository impl
GRDBPromptTemplateRepository.swift # PromptTemplateRepository impl
GRDBProviderCatalogRepository.swift# ProviderCatalogRepository impl
GRDBAppPreferencesRepository.swift # AppPreferencesRepository impl
```

## Where to Look

| Task | File |
|------|------|
| Add new entity | Create `*Record.swift` + `GRDB*Repository.swift`, add protocol to `StorageProtocols.swift` |
| Add DB migration | `DatabaseManager.swift` -> append `migrator.registerMigration("vN")` |
| Provider credential behavior | `ProviderConfigurationRecord.swift` + `CredentialResolver.swift` |
| Streaming message persistence | `ChatPersistenceCoordinator.swift` |
| Query patterns | Any `GRDB*Repository.swift` — all use `DatabasePool.read/write` |
| Image asset storage | `FileMessageAssetStore.swift` — file-based, keyed by asset ID |
| App preferences | `AppPreferencesRecord.swift` + `GRDBAppPreferencesRepository.swift` |

## Conventions

- **Protocol-first**: Define protocol in `StorageProtocols.swift`, implement in `GRDB*Repository.swift`.
- **Record naming**: `*Record` structs conform to GRDB `FetchableRecord`, `PersistableRecord`, `Codable`.
- **Repository naming**: `GRDB*Repository` prefix — always matches protocol name minus prefix.
- **Credential persistence**: Provider API keys live in the `providerConfigurations` SQLite table.
- **JSON hygiene**: `ProviderConfiguration` excludes `apiKey` from generic JSON encoding so legacy settings exports do not leak secrets.
- **Migrations**: Forward-only, sequential (v1-v8+). Never alter existing migrations.
- **DEBUG schema reset**: `eraseDatabaseOnSchemaChange` enabled only in DEBUG builds.
- **DatabaseManager.inMemory()**: Factory for test-only in-memory databases.
- **FileMessageAssetStore**: Stores generated images to `Application Support/Hush/assets/`. Keyed by UUID asset ID.

## Anti-Patterns

- **Do not reintroduce Keychain reads** — provider credentials now resolve from persisted provider configuration only.
- **Never modify existing migrations** — append new `registerMigration("vN+1")`.
- **Never bypass protocols** — consumers depend on `any ConversationRepository`, not `GRDBConversationRepository`.
- **Never use `try!` in persistence** — use `try?` for streaming flushes, `throws` for critical paths.
