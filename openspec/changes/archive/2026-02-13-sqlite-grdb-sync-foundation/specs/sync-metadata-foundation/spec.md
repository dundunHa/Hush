## ADDED Requirements

> Naming note: this spec uses `sync_outbox` as the conceptual name; current implementation maps it to SQLite table `syncOutbox`.

### Requirement: Sync Metadata Fields Exist on Conversations and Messages
The system MUST persist sync metadata alongside each conversation and message record.

#### Scenario: Create sets initial sync metadata
- **WHEN** a conversation or message is created locally
- **THEN** the system SHALL set `updated_at` to the write timestamp
- **AND** the system SHALL set `deleted_at` to null
- **AND** the system SHALL set `source_device_id` to the local device identifier
- **AND** the system SHALL set `sync_state` to a non-synced state (e.g. pending)

#### Scenario: Update bumps updated_at and marks pending
- **WHEN** a conversation or message is updated locally
- **THEN** the system SHALL update `updated_at` to the write timestamp
- **AND** the system SHALL set `sync_state` to a non-synced state (e.g. pending)

#### Scenario: Delete sets deleted_at and marks pending
- **WHEN** a conversation or message is deleted locally
- **THEN** the system SHALL set `deleted_at` to the deletion timestamp
- **AND** the system SHALL set `sync_state` to a non-synced state (e.g. pending)

### Requirement: Outbox Captures Mutations Atomically
The system MUST capture local mutations into an outbox that is transactionally consistent with the base tables.

#### Scenario: Successful mutation appends one outbox record
- **WHEN** a local create/update/delete mutation is committed successfully
- **THEN** the system SHALL append at least one corresponding `sync_outbox` record in the same transaction

#### Scenario: Failed mutation appends no outbox record
- **WHEN** a local mutation is rolled back or fails to commit
- **THEN** the system SHALL NOT append a `sync_outbox` record for that mutation

#### Scenario: Pending outbox entries survive restart
- **WHEN** the app restarts
- **THEN** the system SHALL retain pending `sync_outbox` entries for future dispatch

### Requirement: Minimal Outbox Query API
The system MUST provide a minimal API to read pending outbox items for future sync worker consumption.

#### Scenario: Query returns pending entries deterministically
- **WHEN** the system queries for pending outbox items
- **THEN** the system SHALL return them in deterministic order (e.g. ascending by creation time)
