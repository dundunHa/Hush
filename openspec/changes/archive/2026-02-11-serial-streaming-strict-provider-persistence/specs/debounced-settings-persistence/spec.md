## ADDED Requirements

### Requirement: Debounced Settings Writes
The system SHALL persist settings changes using trailing debounce with a default interval of 1 second.

#### Scenario: Rapid mutations coalesce into one write
- **WHEN** multiple settings mutations occur within one debounce interval
- **THEN** the system SHALL perform at most one persisted write for those mutations

#### Scenario: Spaced mutations produce separate writes
- **WHEN** settings mutations occur with gaps longer than one debounce interval
- **THEN** the system SHALL persist each settled mutation group separately

### Requirement: Explicit Flush on Lifecycle Boundaries
The system MUST provide explicit flush behavior for app lifecycle boundaries.

#### Scenario: App lifecycle flush trigger
- **WHEN** the app reaches a configured flush boundary (for example background or inactive scene phase transition)
- **THEN** the system SHALL synchronously persist latest pending settings before exit from that boundary handler

#### Scenario: Flush drains pending debounce immediately
- **WHEN** a debounce timer is pending and a lifecycle flush boundary is triggered
- **THEN** the system SHALL persist the latest dirty snapshot immediately and cancel the pending debounce timer

#### Scenario: Flush with no dirty settings is a no-op
- **WHEN** a lifecycle flush boundary is triggered and no unsaved settings changes exist
- **THEN** the system SHALL perform no write and SHALL leave persisted state unchanged

### Requirement: Persisted State Converges After Quiet Period
The system MUST guarantee that persisted settings converge to in-memory settings after debounce silence.

#### Scenario: No further mutations after debounce window
- **WHEN** no settings mutations occur for at least one debounce interval
- **THEN** the persisted settings representation SHALL equal the latest in-memory settings snapshot

### Requirement: Persistence Failures Are Visible and Retriable
The system MUST surface persistence failures without silently discarding them and retain unsaved state for retry.

#### Scenario: File write failure occurs
- **WHEN** a settings save attempt fails
- **THEN** the system SHALL emit a user-visible persistence error status containing failure context

#### Scenario: Failed save is retried on next trigger
- **WHEN** a prior save attempt failed and a later debounce tick or lifecycle flush occurs
- **THEN** the system SHALL retry persisting the latest dirty settings snapshot
