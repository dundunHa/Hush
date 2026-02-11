## MODIFIED Requirements

### Requirement: Terminal Request Output Is Durable
The system MUST persist accepted request outputs so terminal request results can be recovered after restart, including when multiple conversations stream concurrently.

#### Scenario: Completed request persists assistant result in owning conversation
- **WHEN** a running request reaches completed terminal state
- **THEN** the system SHALL durably persist the associated assistant message content and terminal status in that request’s owning conversation

#### Scenario: Stopped or failed request preserves partial persisted output
- **WHEN** a running request stops or fails after one or more delta events
- **THEN** the system SHALL preserve and persist the already-assembled assistant content instead of discarding it

#### Scenario: Late events after terminal state do not mutate persisted output
- **WHEN** stale stream events arrive after the request has already entered terminal state
- **THEN** the system SHALL ignore those events for both in-memory transcript and persisted assistant message records

### Requirement: Queue-Full Rejection Remains Persistence-Atomic
The system MUST preserve queue-full atomic rejection semantics for persisted data under concurrent scheduling.

#### Scenario: Queue-full rejection does not create persisted message
- **WHEN** a submission is rejected because the global queued capacity has reached limit
- **THEN** the system SHALL NOT persist a new user message or pending request record for that rejected submission
