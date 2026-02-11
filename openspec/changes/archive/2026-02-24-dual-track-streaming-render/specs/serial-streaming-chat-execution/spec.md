## MODIFIED Requirements

### Requirement: Terminal Request Output Is Durable
The system MUST persist accepted request outputs so terminal request results can be recovered after restart, including when multiple conversations stream concurrently. The dual-track flush architecture MUST NOT affect persistence correctness: the slow-track flush path SHALL remain the sole mechanism for updating the `@Published messages` model and triggering persistence.

#### Scenario: Completed request persists assistant result in owning conversation
- **WHEN** a running request reaches completed terminal state
- **THEN** the system SHALL durably persist the associated assistant message content and terminal status in that request's owning conversation

#### Scenario: Stopped or failed request preserves partial persisted output
- **WHEN** a running request stops or fails after one or more delta events
- **THEN** the system SHALL preserve and persist the already-assembled assistant content instead of discarding it

#### Scenario: Late events after terminal state do not mutate persisted output
- **WHEN** stale stream events arrive after the request has already entered terminal state
- **THEN** the system SHALL ignore those events for both in-memory transcript and persisted assistant message records

#### Scenario: Fast-track does not affect persistence
- **WHEN** the fast-track pushes plain text content to a visible cell during streaming
- **THEN** no persistence operation SHALL be triggered by the fast-track path
- **AND** persistence SHALL only occur through the slow-track updateMessage path and session completion

## ADDED Requirements

### Requirement: handleDelta uses dual-track flush
When a streaming delta arrives, the RequestCoordinator MUST dispatch to both fast-track and slow-track flush paths independently. The fast-track SHALL push content directly to the visible cell. The slow-track SHALL update the messages model on its own throttle schedule.

#### Scenario: Both tracks fire on delta arrival
- **WHEN** a streaming delta text chunk is received by handleDelta
- **THEN** the system SHALL evaluate the fast-track throttle and conditionally push to the visible cell
- **AND** SHALL independently evaluate the slow-track throttle and conditionally call updateMessage

#### Scenario: flushPendingUIUpdate fires both tracks on session end
- **WHEN** a streaming session reaches terminal state (completed, stopped, or failed)
- **THEN** the system SHALL flush any pending fast-track content immediately
- **AND** SHALL flush any pending slow-track content immediately via updateMessage

#### Scenario: First delta inserts message immediately without throttle
- **WHEN** the first streaming delta arrives and creates a new assistant ChatMessage
- **THEN** the system SHALL call `appendMessage` immediately without slow-track throttle delay
- **AND** SHALL record the slow-track flush timestamp to prevent double-flush
- **AND** fast-track SHALL begin operation from the second delta onward

### Requirement: resolveUpdateMode triggers refresh on streaming-to-non-streaming transition
When the last message row was or is in streaming state (old or new `isStreaming` is true), and the content or isStreaming flag has changed, the system MUST return `.streamingRefresh` regardless of the `isActiveConversationSending` state.

#### Scenario: Streaming ends with content change
- **WHEN** the previous last row has `isStreaming == true`
- **AND** the new last row has `isStreaming == false`
- **AND** the message content has changed
- **THEN** `resolveUpdateMode` SHALL return `.streamingRefresh(row:)` for that row

#### Scenario: Streaming ends without content change but isStreaming flips
- **WHEN** the previous last row has `isStreaming == true`
- **AND** the new last row has `isStreaming == false`
- **AND** the message content has NOT changed
- **THEN** `resolveUpdateMode` SHALL return `.streamingRefresh(row:)` for that row

#### Scenario: Non-streaming rows with unchanged content return noOp
- **WHEN** neither the previous nor the new last row has `isStreaming == true`
- **AND** the content has not changed
- **THEN** `resolveUpdateMode` SHALL return `.noOp`

### Requirement: Conversation switch to streaming session triggers immediate content sync
When the user switches to a conversation that has an active streaming request, the system MUST immediately push the current accumulated content to the fast-track path so the UI reflects the latest state without waiting for the next slow-track flush.

#### Scenario: Switch to conversation with active stream
- **WHEN** the user activates conversation X
- **AND** conversation X has a running streaming request with accumulated content
- **THEN** the system SHALL immediately call `pushStreamingContent(conversationId: X, content: accumulated)`

### Requirement: Throttle Task cleanup on stream end, deletion, and eviction
All pending fast-track and slow-track throttle Tasks MUST be explicitly cancelled when a streaming session ends, a conversation is deleted, or a scene is evicted from the hot-scene pool.

#### Scenario: Stream session ends — cancel all throttle Tasks
- **WHEN** a request transitions to terminal state
- **THEN** both `pendingFastFlush` and `pendingUIFlush` Tasks SHALL be cancelled before cleanup

#### Scenario: Conversation deleted — cancel associated throttle Tasks
- **WHEN** a conversation is deleted while it has pending throttle Tasks
- **THEN** all throttle Tasks for that conversation's active requests SHALL be cancelled
