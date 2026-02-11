## ADDED Requirements

### Requirement: Single Active Conversation (v1)
The system MUST maintain exactly one active conversation at runtime.

#### Scenario: Bootstrap loads most recent conversation
- **WHEN** the app starts and at least one conversation exists in storage
- **THEN** the system SHALL select the most recently updated conversation as the active conversation
- **AND** the system SHALL load that conversation's messages into the UI transcript in chronological order

#### Scenario: Bootstrap creates a new conversation when none exist
- **WHEN** the app starts and no conversation exists in storage
- **THEN** the system SHALL create a new conversation, persist it, and set it as active
- **AND** the UI transcript SHALL start empty

#### Scenario: Clear Chat starts a new conversation
- **WHEN** the user triggers "Clear Chat"
- **THEN** the system SHALL create a new conversation and set it as active
- **AND** the system SHALL clear the in-memory transcript for the new conversation
- **AND** the system SHALL NOT delete prior conversations as part of this change

### Requirement: Durable Message Identity and Ordering
The system MUST persist messages with stable identity and deterministic ordering.

#### Scenario: Persisted messages keep stable IDs and timestamps
- **WHEN** the system persists a message
- **THEN** the system SHALL store a stable message identifier
- **AND** the system SHALL store the message role, content, and created timestamp

#### Scenario: Restart restores the same transcript ordering
- **WHEN** the app restarts and loads the active conversation transcript
- **THEN** the system SHALL restore messages in the same chronological order as persisted
- **AND** the restored messages SHALL preserve their persisted identifiers and timestamps
