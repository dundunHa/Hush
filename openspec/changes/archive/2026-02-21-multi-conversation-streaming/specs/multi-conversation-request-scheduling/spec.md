## ADDED Requirements

### Requirement: Global concurrency limit with per-conversation running isolation
The system MUST schedule request execution with a configurable global running limit `N` and MUST enforce at most one running request per conversation.

#### Scenario: Start requests while capacity is available
- **WHEN** queued requests exist and current global running count is below `N`
- **THEN** the scheduler SHALL start additional requests until either `N` is reached or no eligible queued request remains

#### Scenario: Per-conversation running cap is enforced
- **WHEN** a conversation already has one running request and another request from the same conversation reaches queue head
- **THEN** the scheduler SHALL NOT start that second request until the first request for that conversation reaches terminal state

### Requirement: Deterministic active-priority scheduling with fairness
The scheduler MUST use deterministic selection order: active conversation priority, background round-robin, and quota-based anti-starvation.

#### Scenario: Active conversation is prioritized for next slot
- **WHEN** a running slot becomes available and active conversation queue has eligible requests
- **THEN** the scheduler SHALL select the active conversation queue head before non-aged background requests

#### Scenario: Background fairness uses per-conversation round-robin
- **WHEN** active conversation queue is empty and multiple background conversation queues are non-empty
- **THEN** the scheduler SHALL select the next queue by round-robin across conversation IDs and dequeue only that queue head

#### Scenario: Quota-based anti-starvation promotes aged requests
- **WHEN** a queued request has waited at least `T` seconds and the scheduler has granted `K` active-priority selections since last aged grant
- **THEN** the scheduler SHALL grant one eligible aged request before granting another active-priority selection

### Requirement: Queue capacity is bounded and rejection is atomic
The system MUST preserve a bounded global queued capacity of 5 (excluding running requests) and MUST reject overflow submissions atomically.

#### Scenario: Queue-full submission is atomically rejected
- **WHEN** a user submits a request while queued count is at capacity
- **THEN** the system SHALL reject the submission
- **AND** SHALL NOT append a new user message to transcript
- **AND** SHALL NOT enqueue a request
- **AND** SHALL NOT persist user or assistant records for that rejected submission
