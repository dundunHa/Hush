## ADDED Requirements

### Requirement: Long non-streaming assistant messages should support progressive rendering
The system SHALL avoid blocking the switch frame for long non-streaming assistant messages when no cached render output exists. In this case, it SHALL first present readable fallback text and then asynchronously apply rich rendered output.

#### Scenario: Long message cache miss renders progressively
- **WHEN** an assistant message longer than the configured progressive threshold is displayed in non-streaming mode and no cached render output is available
- **THEN** the system SHALL display readable fallback text immediately and SHALL apply rich rendering asynchronously without crashing

#### Scenario: High-priority cache hit renders immediately
- **WHEN** an assistant message longer than the configured progressive threshold is displayed in non-streaming mode with cached render output available and its priority is high (within the latest N messages)
- **THEN** the system SHALL apply rich rendering immediately

#### Scenario: Non-critical cache hit is queued to avoid switch-time burst
- **WHEN** an assistant message has cached render output available but its priority is not high (visible, deferred, or idle)
- **THEN** the system SHALL enqueue the cached output through the render scheduler to avoid bursty main-thread layout during conversation switches

### Requirement: Conversation switch should prewarm a bounded set of recent conversations
After bootstrap, the system SHALL prewarm a bounded number of recent non-active conversations and keep this behavior within configured limits to avoid excessive startup cost.

#### Scenario: Startup prewarm loads only configured recent conversations
- **WHEN** startup prewarm runs
- **THEN** it SHALL load no more than the configured conversation count and message page size for non-active conversations

#### Scenario: Switching to a prewarmed conversation applies cached snapshot first
- **WHEN** the user switches to a conversation that was prewarmed
- **THEN** the system SHALL apply cached snapshot state immediately before async refresh

### Requirement: Render scheduling should deduplicate identical requests
The system SHALL deduplicate repeated render requests with identical input fingerprint (content, width, style, streaming flag) to reduce redundant work during rapid state changes.

#### Scenario: Duplicate render request is ignored
- **WHEN** a render request arrives with the same fingerprint as the most recent pending/applied request
- **THEN** the controller SHALL skip redundant render scheduling

### Requirement: Non-streaming rich rendering should prioritize latest and visible assistant messages
The system SHALL schedule non-streaming assistant rich renders by conversation-local priority to avoid blocking the switch frame.

#### Scenario: Latest three assistant messages are rendered first
- **WHEN** a conversation switch triggers multiple non-streaming assistant cache misses
- **THEN** assistant messages with `rankFromLatest < 3` SHALL be processed before lower-priority items

#### Scenario: Visible assistant messages are promoted over offscreen deferred work
- **WHEN** an assistant message enters the viewport while deferred/offscreen work exists
- **THEN** the visible message SHALL be processed first according to the priority mapping

#### Scenario: Offscreen idle work respects delay budget
- **WHEN** an assistant message is offscreen and outside the near-latest window
- **THEN** its rich render work SHALL not execute earlier than the configured idle delay

### Requirement: Conversation switch generations should prevent stale rich apply
The system SHALL isolate queued non-streaming render work by conversation switch generation so stale results cannot overwrite current conversation UI.

#### Scenario: Old generation render callback is dropped
- **WHEN** queued work from an older conversation generation completes after a new generation became active
- **THEN** the callback SHALL be ignored and must not update current output
