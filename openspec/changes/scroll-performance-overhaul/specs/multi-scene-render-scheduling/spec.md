## ADDED Requirements

### Requirement: ConversationRenderScheduler supports live scroll gating
The scheduler MUST accept a `setLiveScrolling(_:)` call that gates the execution of non-streaming render work items. When live scrolling is active, the scheduler MUST NOT execute render closures, but SHALL retain queued items for later processing.

#### Scenario: Scheduler pauses execution during live scroll
- **WHEN** `setLiveScrolling(true)` has been called
- **AND** the worker loop reaches the top of its iteration
- **THEN** the scheduler SHALL NOT call `selectNextWork` to dequeue any work item
- **AND** SHALL sleep for a bounded polling interval (100ms) before re-checking the scroll state

#### Scenario: Scheduler resumes execution when scroll ends
- **WHEN** `setLiveScrolling(false)` is called after a period of live scrolling
- **THEN** the scheduler SHALL resume processing queued work items in priority order
- **AND** SHALL NOT drop any items that were queued during the scroll period

#### Scenario: Stale pruning continues during scroll
- **WHEN** live scrolling is active
- **AND** `setSceneConfiguration` is called (e.g., conversation switch during scroll)
- **THEN** stale work items SHALL still be pruned per existing rules
- **AND** only non-stale items SHALL be processed after scroll ends

#### Scenario: Budget interval still applies after scroll ends
- **WHEN** live scrolling ends and multiple queued items are ready
- **THEN** the scheduler SHALL still space execution by `budgetInterval` between items
- **AND** SHALL NOT execute all queued items in a burst
