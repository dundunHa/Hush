## ADDED Requirements

### Requirement: Single Active Remote Stream
The system MUST allow at most one active remote generation stream at any time.

#### Scenario: First send starts active stream
- **WHEN** the user submits a message while no request is active
- **THEN** the system SHALL create exactly one active request and start consuming provider stream events

#### Scenario: Additional send does not create a second active stream
- **WHEN** the user submits another message while one request is active
- **THEN** the system SHALL NOT start a second active stream concurrently

### Requirement: Deterministic Pending Queue
The system MUST preserve request order for messages submitted during an active request by using a bounded FIFO pending queue.

#### Scenario: Send while busy is queued
- **WHEN** the user submits a message while a request is active and queue capacity is available
- **THEN** the system SHALL append a pending queue item after existing pending items

#### Scenario: Queue enforces fixed default capacity
- **WHEN** pending queue length reaches `5`
- **THEN** the system SHALL treat the queue as full for new submissions

#### Scenario: Queue advances after active request finishes
- **WHEN** the active request reaches completed, failed, or stopped terminal state and pending items exist
- **THEN** the system SHALL start the oldest pending request next

#### Scenario: Queue full rejection is explicit and atomic
- **WHEN** the user submits a message and the pending queue is at maximum capacity
- **THEN** the system SHALL reject the new submission with a visible queue-full error
- **AND** the system SHALL NOT append a new user message or pending queue item for the rejected submission

### Requirement: Submission Snapshot Integrity
The system MUST execute queued requests using prompt/provider/model/parameter values captured at submission time.

#### Scenario: Queued request uses captured snapshot
- **WHEN** a request is queued and the user edits provider/model/parameters before it starts
- **THEN** the dequeued request SHALL use the captured submission snapshot instead of current mutable settings

### Requirement: Explicit Stop and Cancellation Semantics
The system MUST provide explicit stop behavior that cancels only the active request.

#### Scenario: Stop cancels active request
- **WHEN** the user triggers stop during an active request
- **THEN** the system SHALL cancel the active provider stream and mark that request as stopped

#### Scenario: Stop preserves pending queue and auto-advances
- **WHEN** the user stops an active request and pending items exist
- **THEN** the system SHALL keep pending items in FIFO order and SHALL start the oldest pending request next

#### Scenario: Late events after stop are ignored
- **WHEN** stream events arrive after the request has been canceled
- **THEN** the system SHALL ignore those stale events and SHALL NOT mutate message content

#### Scenario: Stop without active request is no-op
- **WHEN** the user triggers stop while no request is active
- **THEN** the system SHALL leave message and queue state unchanged and SHALL emit a user-visible no-op status update

### Requirement: Incremental Assistant Message Assembly
The system MUST assemble assistant output incrementally from stream events for each request.

#### Scenario: First delta initializes one in-progress assistant message
- **WHEN** the first provider delta event is received for an active request
- **THEN** the system SHALL create one in-progress assistant message for that request

#### Scenario: Later deltas append to the same assistant message
- **WHEN** additional provider delta events are received for an active request
- **THEN** the system SHALL append content to the same in-progress assistant message for that request

#### Scenario: Completion finalizes message state
- **WHEN** a provider completed event is received
- **THEN** the system SHALL mark the in-progress assistant message as complete and clear active request state

#### Scenario: Partial output is preserved on stop or failure
- **WHEN** a request stops or fails after one or more delta events
- **THEN** the system SHALL preserve the already-assembled assistant content in the transcript and clear active request state
