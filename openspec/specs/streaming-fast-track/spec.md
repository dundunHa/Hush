# Streaming Fast Track

## Purpose
Define the fast-track streaming UI update path that improves perceived responsiveness while preserving slow-track model consistency and persistence behavior.

## Requirements

### Requirement: Fast-track streaming pushes plain text directly to visible cell
During active streaming, the system MUST push accumulated plain text content directly to the visible streaming cell via the AppKit object graph (AppContainer → HotScenePool → ConversationViewController → MessageTableView → cell), bypassing the SwiftUI update cycle and NSTableView reloadData path. The target cell MUST be located by **messageID** (not by assuming last row index).

#### Scenario: Fast-track updates visible streaming cell
- **WHEN** a streaming delta arrives for the active conversation
- **AND** the streaming cell (identified by messageID) is visible in the table view
- **THEN** the system SHALL locate the target row by scanning `rows` for matching messageID
- **AND** SHALL set the cell's body label to the accumulated plain text content
- **AND** SHALL NOT trigger SwiftUI's `updateNSViewController` for this update
- **AND** SHALL NOT call `tableView.reloadData` or `reloadData(forRowIndexes:)`

#### Scenario: Fast-track degrades when cell is not visible
- **WHEN** a streaming delta arrives for the active conversation
- **AND** the user has scrolled up so the streaming cell is not visible
- **THEN** the system SHALL skip the fast-track update without error
- **AND** the slow-track path SHALL still update the messages model

#### Scenario: Fast-track only applies to active conversation
- **WHEN** a streaming delta arrives for a background (non-active) conversation
- **THEN** the system SHALL NOT attempt fast-track delivery
- **AND** SHALL rely on the existing slow-track + markNeedsReload path

#### Scenario: Fast-track coalesces identical content
- **WHEN** consecutive fast-track flushes carry identical content
- **THEN** the system SHALL skip the redundant bodyLabel assignment

### Requirement: Fast-track throttle interval is configurable and defaults to 30ms
The fast-track flush interval MUST be defined as a constant in RenderConstants and MUST default to 30 milliseconds.

#### Scenario: Fast-track updates at configured interval
- **WHEN** streaming deltas arrive faster than the fast-track interval (30ms)
- **THEN** the system SHALL coalesce deltas and flush at most once per interval
- **AND** each flush SHALL use the latest accumulated content

#### Scenario: Fast-track interval is independent of slow-track
- **WHEN** both fast-track and slow-track are active during streaming
- **THEN** each SHALL operate on its own independent throttle timer
- **AND** neither SHALL block or depend on the other

### Requirement: Fast-track updates row height only when height actually changes
After setting plain text on the streaming cell, the system MUST check whether `bodyLabel.intrinsicContentSize.height` has changed compared to the previously recorded value. Only when the height differs SHALL the system call `noteHeightOfRows(withIndexesChanged:)`.

#### Scenario: Row height updates after text crosses line boundary
- **WHEN** the fast-track sets new plain text content
- **AND** the bodyLabel's intrinsicContentSize.height differs from the previously recorded height
- **THEN** the system SHALL call `tableView.noteHeightOfRows(withIndexesChanged:)` for the streaming row
- **AND** SHALL record the new height value

#### Scenario: Row height does not update when height is unchanged
- **WHEN** the fast-track sets new plain text content
- **AND** the bodyLabel's intrinsicContentSize.height is the same as previously recorded
- **THEN** the system SHALL NOT call `noteHeightOfRows`

### Requirement: Fast-track maintains tail-follow scroll behavior
After each fast-track update, the system MUST scroll to bottom if the user has not manually scrolled up (i.e., the tail-follow state machine indicates following).

#### Scenario: Auto-scroll during fast-track streaming
- **WHEN** the fast-track updates the streaming cell
- **AND** the tail-follow state indicates `isFollowingTail == true`
- **THEN** the system SHALL scroll the table view to make the last row visible

#### Scenario: No scroll when user has scrolled up
- **WHEN** the fast-track updates the streaming cell
- **AND** the user has scrolled up (`isFollowingTail == false`)
- **THEN** the system SHALL NOT perform any scroll adjustment

### Requirement: Slow-track continues to update messages model
The slow-track path MUST continue to call `AppContainer.updateMessage(at:inConversation:content:)` to update the `@Published messages` array, maintaining model consistency for persistence, conversation switching, and final rich rendering. The slow-track throttle interval is controlled at the RequestCoordinator layer (~200ms) and does NOT modify RenderController's coalesce interval.

#### Scenario: Slow-track updates messages array
- **WHEN** the slow-track flush timer fires during streaming
- **THEN** the system SHALL call `updateMessage` with the latest accumulated content
- **AND** the `@Published messages` array SHALL reflect the update

#### Scenario: Slow-track interval defaults to 200ms
- **WHEN** streaming is active
- **THEN** the slow-track SHALL flush at most once per 200 milliseconds (configurable via RenderConstants)
- **AND** the RenderController's own coalesce interval SHALL remain at 50ms unchanged

### Requirement: Fast-track path traversal uses existing object references
The fast-track MUST traverse the object graph via `AppContainer.hotScenePool → HotScenePool.sceneFor(conversationID:) → ConversationViewController → MessageTableView`. No new coupling mechanisms (NotificationCenter, Combine publishers, global singletons) SHALL be introduced.

#### Scenario: Fast-track uses HotScenePool to find active scene
- **WHEN** the fast-track needs to deliver content for conversation X
- **THEN** it SHALL obtain the ConversationViewController via `hotScenePool.sceneFor(conversationID: X)`
- **AND** SHALL forward the content through ConversationViewController to MessageTableView

### Requirement: Cell-level anti-regression prevents slow-track from overwriting newer fast-track content
During streaming, when slow-track's `cell.configure` runs with stale model content, the cell MUST NOT regress to showing shorter/older plain text than what fast-track has already displayed.

#### Scenario: Slow-track configure with stale content during streaming
- **WHEN** slow-track triggers `cell.configure` with content shorter than what fast-track has displayed
- **AND** the cell is still streaming (`isStreaming == true` for both current and incoming)
- **THEN** the cell SHALL skip the Phase 1 plain text write
- **AND** SHALL still trigger RenderController for rich rendering

#### Scenario: Slow-track configure with final content (streaming ended)
- **WHEN** slow-track triggers `cell.configure` with `isStreaming == false`
- **THEN** the cell SHALL unconditionally accept the content write
- **AND** SHALL reset the anti-regression counter (`streamingDisplayedLength = 0`)

#### Scenario: Anti-regression state resets on cell reuse
- **WHEN** a cell is recycled via `prepareForReuse`
- **THEN** `streamingDisplayedLength` SHALL be reset to 0

### Requirement: First delta triggers immediate slow-track insertion without throttle
The first streaming delta for a new assistant message MUST result in immediate message creation and UI insertion, not subject to the 200ms slow-track throttle.

#### Scenario: First delta creates and displays message immediately
- **WHEN** the first streaming delta arrives and no assistant message exists yet
- **THEN** the system SHALL create the ChatMessage and call `appendMessage` immediately
- **AND** SHALL NOT apply slow-track throttle delay to this first insertion
- **AND** fast-track SHALL begin from delta#2 onward

### Requirement: Conversation switch to streaming conversation triggers immediate content sync
When the user switches to a conversation that has an active streaming session, the system MUST immediately push the current accumulated content to the UI via the fast-track path.

#### Scenario: Switch to actively streaming conversation
- **WHEN** the user switches to conversation X
- **AND** conversation X has a running streaming request
- **THEN** the system SHALL call `pushStreamingContent` with the current accumulated content for X
- **AND** the UI SHALL immediately reflect the latest streaming content

### Requirement: Throttle Tasks are cancellable and cleaned up
All fast-track and slow-track throttle Tasks MUST be explicitly cancellable and cleaned up on stream end, conversation deletion, and scene eviction.

#### Scenario: Stream ends — pending Tasks cancelled
- **WHEN** a streaming session reaches terminal state
- **THEN** all pending fast-track and slow-track throttle Tasks for that request SHALL be cancelled
- **AND** final content SHALL be flushed immediately before cancellation

#### Scenario: Conversation deleted during streaming — Tasks cancelled
- **WHEN** a conversation is deleted while it has active streaming
- **THEN** all pending throttle Tasks for that conversation's requests SHALL be cancelled
