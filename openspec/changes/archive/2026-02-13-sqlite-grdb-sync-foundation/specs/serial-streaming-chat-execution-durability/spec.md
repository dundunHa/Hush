## ADDED Requirements

### Requirement: Queue-Full Rejection Does Not Write to Storage
The system MUST preserve the existing queue-full atomic rejection behavior when persistence is enabled.

#### Scenario: Queue-full rejection produces zero durable writes
- **WHEN** the user submits a message and the pending queue is at maximum capacity
- **THEN** the system SHALL reject the submission with a visible queue-full error
- **AND** the system SHALL NOT persist a user message record
- **AND** the system SHALL NOT persist an assistant message record
- **AND** the system SHALL NOT create any sync outbox entry for the rejected submission

### Requirement: Streaming Persistence Semantics
The system MUST durably persist the streaming assembly lifecycle without changing existing request semantics.

#### Scenario: Accepted submission persists the user message
- **WHEN** the user submits a message and the submission is accepted (not rejected due to queue-full)
- **THEN** the system SHALL persist the user message record in the active conversation

#### Scenario: First delta creates one durable in-progress assistant message
- **WHEN** the first provider delta event is received for an active request
- **THEN** the system SHALL create exactly one assistant message record correlated to that request
- **AND** the assistant message record SHALL be marked as in-progress (draft/streaming)

#### Scenario: Later deltas update the same durable assistant message
- **WHEN** additional provider delta events are received for an active request
- **THEN** the system SHALL update the same assistant message record content in place

#### Scenario: Terminal event finalizes the durable assistant message
- **WHEN** a request reaches completed, failed, or stopped terminal state
- **THEN** the system SHALL persist the terminal state for the correlated assistant message
- **AND** the terminal state SHALL be stable across app restart

#### Scenario: Late events after terminal state do not mutate durable records
- **WHEN** stream events arrive after a request has reached terminal state
- **THEN** the system SHALL ignore those stale events
- **AND** the system SHALL NOT mutate persisted user or assistant message records

### Requirement: Crash/Kill Recovery Finalizes In-Progress Records
The system MUST provide deterministic recovery when the app exits before a terminal state is durably recorded.

#### Scenario: Restart finalizes in-progress assistant messages as interrupted
- **WHEN** the app starts and persisted assistant messages exist in an in-progress state
- **THEN** the system SHALL mark those messages as `interrupted` (or an equivalent terminal state)
- **AND** the system SHALL NOT attempt to resume streaming for the interrupted messages
