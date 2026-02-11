## ADDED Requirements

### Requirement: Live scroll state detection via NSScrollView notifications
MessageTableView MUST detect live scroll state by observing `NSScrollView.willStartLiveScrollNotification` and `NSScrollView.didEndLiveScrollNotification` on the `scrollView` instance (not the contentView). An `isLiveScrolling` boolean flag MUST reflect the current state.

#### Scenario: Scroll begins sets isLiveScrolling to true
- **WHEN** `willStartLiveScrollNotification` is received
- **THEN** `isLiveScrolling` SHALL be set to `true`

#### Scenario: Scroll ends sets isLiveScrolling to false
- **WHEN** `didEndLiveScrollNotification` is received
- **THEN** `isLiveScrolling` SHALL be set to `false`

#### Scenario: Keyboard arrow key scrolling does not trigger live scroll
- **WHEN** the user scrolls using keyboard arrow keys (no live scroll notifications)
- **THEN** `isLiveScrolling` SHALL remain `false`
- **AND** existing `updatePinnedState()` behavior SHALL be unaffected

#### Scenario: Safety timeout restores isLiveScrolling on missing didEnd
- **WHEN** `willStartLiveScrollNotification` was received
- **AND** no `didEndLiveScrollNotification` has been received within 3 seconds
- **THEN** `isLiveScrolling` SHALL be reset to `false`

#### Scenario: Conversation switch resets isLiveScrolling
- **WHEN** `apply()` is called with a new switch generation (`generationChanged == true`)
- **AND** `isLiveScrolling` is currently `true`
- **THEN** `isLiveScrolling` SHALL be reset to `false`
- **AND** the scroll gate state SHALL be propagated to the scheduler via `runtime.setLiveScrolling(false)`

### Requirement: Lookahead prewarm is suspended during live scroll
The `scheduleLookaheadPrewarm()` method MUST NOT schedule any prewarm tasks while `isLiveScrolling` is true. After scroll ends, a single debounced prewarm SHALL be triggered.

#### Scenario: Prewarm skipped during live scroll
- **WHEN** `updatePinnedState()` is called during live scroll
- **THEN** `scheduleLookaheadPrewarm()` SHALL return immediately without scanning rows or creating tasks

#### Scenario: Prewarm fires after scroll ends with debounce
- **WHEN** `didEndLiveScrollNotification` is received
- **THEN** a prewarm SHALL be scheduled after a debounce interval (200ms)
- **AND** the prewarm SHALL use the current visible rows at that time

#### Scenario: Rapid scroll restart cancels pending debounce prewarm
- **WHEN** a debounce prewarm is pending
- **AND** `willStartLiveScrollNotification` is received again
- **THEN** the pending debounce prewarm SHALL be cancelled

### Requirement: ConversationRenderScheduler pauses work consumption during live scroll
The scheduler's worker loop MUST NOT execute render work items while `isLiveScrolling` is true. It SHALL resume processing when scroll ends.

#### Scenario: Scheduler skips execute during scroll
- **WHEN** the scheduler selects a work item for execution
- **AND** `isLiveScrolling` is true
- **THEN** the scheduler SHALL wait (yield/sleep) instead of executing the render closure
- **AND** the work item SHALL remain in the queue

#### Scenario: Scheduler resumes after scroll ends
- **WHEN** `isLiveScrolling` transitions from true to false
- **THEN** the scheduler SHALL resume processing queued work items in priority order

#### Scenario: Streaming renders are not affected by scroll gate
- **WHEN** a streaming render is in progress via RenderController's streaming path
- **THEN** the scroll gate SHALL NOT affect streaming render coalescing
- **AND** streaming content SHALL continue to update at the configured coalesce interval

### Requirement: Scroll gate state is propagated via MessageRenderRuntime
MessageRenderRuntime MUST expose a method to set the live scroll state, which propagates to the ConversationRenderScheduler.

#### Scenario: MessageTableView sets scroll state on runtime
- **WHEN** live scroll state changes in MessageTableView
- **THEN** MessageTableView SHALL call `runtime.setLiveScrolling(_:)` to propagate the state

#### Scenario: Runtime forwards scroll state to scheduler
- **WHEN** `setLiveScrolling(_:)` is called on MessageRenderRuntime
- **THEN** it SHALL forward the value to `ConversationRenderScheduler.setLiveScrolling(_:)`
