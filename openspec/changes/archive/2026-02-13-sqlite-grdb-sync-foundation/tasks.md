## 1. Storage Foundation

- [x] 1.1 Add `GRDB.swift` dependency and wire build settings for the app target.
- [x] 1.2 Create a database bootstrap component that opens SQLite in Application Support and configures lifecycle-safe access.
- [x] 1.3 Define storage protocols/repositories for conversations, messages, provider credentials reference, and sync outbox.

## 2. Schema and Migrations

- [x] 2.1 Create initial schema migration for `conversations` and `messages` with stable IDs and ordering fields.
- [x] 2.2 Add sync metadata fields (`updated_at`, `deleted_at`, `sync_state`, `source_device_id`) and required indexes.
- [x] 2.3 Create `sync_outbox` table and migration with operation type, entity identity, status, and retry bookkeeping columns.
- [x] 2.4 Add migration tests to verify idempotent startup and expected schema versioning behavior.

## 3. Chat Persistence Integration

- [x] 3.1 Implement v1 "single active conversation" semantics: load the most recent conversation on bootstrap; `Clear Chat` creates and switches to a new conversation (old conversations retained; no conversation-switch UI in this change).
- [x] 3.2 Load persisted messages for the active conversation during app bootstrap and populate initial UI state.
- [x] 3.3 Persist accepted user submissions atomically and preserve queue-full rejection no-write behavior.
- [x] 3.4 Persist streaming assistant assembly by creating one draft record on first delta and updating it on subsequent deltas.
- [x] 3.5 Persist terminal request states (completed/failed/stopped) with preserved partial content semantics.
- [x] 3.6 Ensure stale events after terminal state do not mutate persisted or in-memory assistant messages.
- [x] 3.7 Define crash/kill recovery behavior: on next launch, any in-progress assistant record is finalized as `interrupted` (or equivalent terminal) and is not mutated by late events.
- [x] 3.8 Add streaming persistence throttling/coalescing and ensure terminal-state flush produces the final durable content.

## 4. Sync Metadata and Outbox Capture

- [x] 4.1 Mark local create/update/delete mutations with sync metadata transitions.
- [x] 4.2 Append outbox entries for each successful local mutation in the same transaction.
- [x] 4.3 Retain pending outbox entries across app restart and failed dispatch attempts.
- [x] 4.4 Add a minimal outbox query API for future sync worker consumption.

## 5. Secure Credential Storage

- [x] 5.1 Implement Keychain adapter for create/read/update/delete of provider secrets.
- [x] 5.2 Store only non-secret credential references in persisted configuration (e.g. settings / database), never secret material.
- [x] 5.3 Update provider request path to resolve credential references from Keychain before invocation (no silent fallback).
- [x] 5.4 Surface explicit credential-resolution errors when Keychain items are missing or inaccessible.

## 6. Verification and Regression Coverage

- [x] 6.1 Add repository tests for conversation recovery, message ordering, and terminal-state durability.
- [x] 6.2 Add lifecycle tests for queue-full atomic persistence behavior and streaming update persistence semantics.
- [x] 6.3 Add tests for sync metadata and outbox retry-safe behavior across restart boundaries.
- [x] 6.4 Add Keychain integration tests (or test doubles) for secret isolation and credential rotation paths.
- [x] 6.5 Run full test suite and document verification results for apply review.
