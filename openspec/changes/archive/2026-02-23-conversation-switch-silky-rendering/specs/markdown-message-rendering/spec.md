## MODIFIED Requirements

### Requirement: Rendering caches are bounded to protect memory
The system MUST bound internal rendering caches (message render results and math render results) to avoid unbounded memory growth during long sessions. Cache eviction behavior MUST be deterministic to support unit testing. The message render cache MUST support conversation-aware eviction protection so that recently-visited conversations' render results are not prematurely evicted by less relevant entries.

#### Scenario: Cache entries do not exceed configured capacity
- **WHEN** the system renders more unique messages/formulas than the configured cache capacity
- **THEN** the system SHALL evict older entries and SHALL keep cache size within the configured capacity

#### Scenario: Protected entries are evicted only after unprotected entries
- **WHEN** the cache is at capacity and needs to evict
- **AND** both protected and unprotected entries exist
- **THEN** the system SHALL evict the least-recently-used unprotected entry first

### Requirement: Conversation switch should prewarm a bounded set of recent conversations
After bootstrap, the system SHALL prewarm a bounded number of recent non-active conversations and keep this behavior within configured limits to avoid excessive startup cost. Additionally, the system SHALL prewarm on switch-away events and during idle periods to maximize cache hit rates on subsequent switches.

#### Scenario: Startup prewarm loads only configured recent conversations
- **WHEN** startup prewarm runs
- **THEN** it SHALL load no more than the configured conversation count (at least 4) and message page size (at least 8 assistant messages) for non-active conversations

#### Scenario: Switching to a prewarmed conversation applies cached snapshot first
- **WHEN** the user switches to a conversation that was prewarmed
- **THEN** the system SHALL apply cached snapshot state immediately before async refresh

#### Scenario: Switch-away triggers prewarm for adjacent conversations
- **WHEN** the user switches away from a conversation
- **THEN** the system SHALL asynchronously prewarm sidebar-adjacent conversations that are not yet in the RenderCache
- **AND** prewarm SHALL execute on `@MainActor` at utility priority (not on a detached background thread)

#### Scenario: Idle period triggers prewarm for hot conversations
- **WHEN** no streaming activity and no user input occurs for the configured idle period
- **THEN** the system SHALL prewarm the RenderCache for hot conversations whose tail messages are not yet cached
- **AND** prewarm SHALL be cancellable and SHALL yield between each message render

#### Scenario: Prewarm method supports cancellation
- **WHEN** `MessageContentRenderer.prewarm(inputs:)` is executing
- **THEN** it SHALL check `Task.isCancelled` between each message render
- **AND** SHALL yield execution between iterations to avoid blocking the main thread
- **AND** already-rendered cache entries SHALL be retained even if the remaining prewarm is cancelled
