# HushStorage

GRDB-backed persistence layer with protocol-driven repositories, Keychain credential management, and streaming coordination.

## Structure

```
StorageProtocols.swift             # All repository protocol definitions
DatabaseManager.swift              # DatabasePool setup, WAL mode, migrations v1-v8
ChatPersistenceCoordinator.swift   # @MainActor streaming flush + finalization
KeychainAdapter.swift              # macOS Security framework wrapper
CredentialResolver.swift           # Bridges credentialRef keys → Keychain secrets
ConversationRecord.swift           # GRDB Record for conversations
MessageRecord.swift                # GRDB Record for messages
SyncOutboxRecord.swift             # GRDB Record for sync outbox entries
GRDBConversationRepository.swift   # ConversationRepository impl
GRDBMessageRepository.swift        # MessageRepository impl
GRDBSyncOutboxRepository.swift     # SyncOutboxRepository impl
GRDBCredentialRefRepository.swift  # CredentialReferenceRepository impl
GRDBProviderConfigRepository.swift # ProviderConfigurationRepository impl
GRDBAgentPresetRepository.swift    # AgentPresetRepository impl
GRDBPromptTemplateRepository.swift # PromptTemplateRepository impl
GRDBProviderCatalogRepository.swift# ProviderCatalogRepository impl
```

## Where to Look

| Task | File |
|------|------|
| Add new entity | Create `*Record.swift` + `GRDB*Repository.swift`, add protocol to `StorageProtocols.swift` |
| Add DB migration | `DatabaseManager.swift` → append `migrator.registerMigration("vN")` |
| Credential CRUD | `KeychainAdapter.swift` (raw Keychain) or `CredentialResolver.swift` (high-level) |
| Streaming message persistence | `ChatPersistenceCoordinator.swift` |
| Query patterns | Any `GRDB*Repository.swift` — all use `DatabasePool.read/write` |

## Conventions

- **Protocol-first**: Define protocol in `StorageProtocols.swift`, implement in `GRDB*Repository.swift`.
- **Record naming**: `*Record` structs conform to GRDB `FetchableRecord`, `PersistableRecord`, `Codable`.
- **Repository naming**: `GRDB*Repository` prefix — always matches protocol name minus prefix.
- **Keychain service pattern**: `com.dundunha.hush.provider.{providerID}`.
- **Credential indirection**: Config stores `credentialRef` string, never raw secret. `CredentialResolver` maps ref → Keychain lookup.
- **Migrations**: Forward-only, sequential (v1–v8). Never alter existing migrations.
- **DEBUG schema reset**: `eraseDatabaseOnSchemaChange` enabled only in DEBUG builds.
- **DatabaseManager.inMemory()**: Factory for test-only in-memory databases.

## Anti-Patterns

- **Never store secrets in config/DB** — Keychain only, via `KeychainAdapter`.
- **Never modify existing migrations** — append new `registerMigration("vN+1")`.
- **Never bypass protocols** — consumers depend on `any ConversationRepository`, not `GRDBConversationRepository`.
- **Never use `try!` in persistence** — use `try?` for streaming flushes, `throws` for critical paths.
