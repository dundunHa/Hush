## ADDED Requirements

### Requirement: RenderCache capacity supports multi-conversation workloads
The RenderCache MUST have a capacity of at least 256 entries to sustain render results across multiple recently-visited conversations without excessive eviction.

#### Scenario: Capacity accommodates 4 conversations with 15 assistant messages each
- **WHEN** 4 different conversations each contribute 15 cached render outputs at the same width and style
- **THEN** the RenderCache SHALL retain all 60 entries without eviction

#### Scenario: Capacity is configurable at construction time
- **WHEN** a RenderCache is constructed with a custom capacity value
- **THEN** the cache SHALL use that value as its maximum entry count

### Requirement: RenderCache provides conversation-aware eviction protection
The RenderCache MUST support marking cache entries as protected for a given conversation ID. When eviction is necessary, the cache MUST prefer evicting unprotected entries before protected entries.

#### Scenario: Protected entries survive eviction when unprotected entries exist
- **WHEN** the cache is at capacity and a new entry is inserted
- **AND** the least-recently-used entry is protected for a conversation
- **AND** there exists an unprotected entry in the cache
- **THEN** the cache SHALL evict the least-recently-used unprotected entry instead

#### Scenario: Protected entries are evicted when no unprotected entries remain
- **WHEN** the cache is at capacity and all entries are protected
- **AND** a new entry is inserted
- **THEN** the cache SHALL evict the least-recently-used entry regardless of protection status

#### Scenario: An entry protected by multiple conversations remains protected until all protections are removed
- **WHEN** an entry is marked protected for conversation A and conversation B
- **AND** protection is removed for conversation A
- **THEN** the entry SHALL still be considered protected (by conversation B)

#### Scenario: Protection can be cleared for a conversation
- **WHEN** `clearProtection(conversationID:)` is called
- **THEN** all entries protected solely by that conversation SHALL lose their protection
- **AND** entries also protected by other conversations SHALL remain protected

### Requirement: Switch-away prewarm populates RenderCache for adjacent conversations
When the user switches away from a conversation, the system MUST asynchronously prewarm the RenderCache for sidebar-adjacent conversations that are not already cached.

#### Scenario: Switching triggers prewarm for next sidebar conversation
- **WHEN** user switches from conversation A to conversation B
- **AND** conversation C is adjacent to A in the sidebar and its tail messages are not in RenderCache
- **THEN** the system SHALL asynchronously render and cache the tail assistant messages of conversation C

#### Scenario: Prewarm does not block the switch
- **WHEN** switch-away prewarm is triggered
- **THEN** the prewarm work SHALL execute asynchronously at utility priority on the @MainActor
- **AND** SHALL NOT delay the activation of the target conversation

#### Scenario: Prewarm uses fixed chat content width
- **WHEN** any prewarm (switch-away, idle, startup, streaming-complete) executes
- **THEN** it SHALL use `HushSpacing.chatContentMaxWidth` as the `availableWidth` for render inputs
- **AND** SHALL NOT depend on any view's current bounds

#### Scenario: Already-cached conversations are skipped
- **WHEN** the adjacent conversation's tail messages are already in RenderCache
- **THEN** the system SHALL NOT re-render those messages

### Requirement: Idle prewarm maintains RenderCache for recently-visited conversations
When the active conversation has no streaming activity and no user input for a configurable idle period, the system MUST prewarm RenderCache entries for hot conversations whose tail messages are not yet cached.

#### Scenario: Idle timeout triggers prewarm
- **WHEN** the active conversation has no streaming and no user input for 2 seconds
- **AND** a hot conversation's latest K assistant messages are not in RenderCache
- **THEN** the system SHALL asynchronously render and cache those messages

#### Scenario: Idle prewarm is cancelled on user activity
- **WHEN** idle prewarm is in progress
- **AND** the user starts typing or switches conversation
- **THEN** the pending idle prewarm work SHALL be cancelled
- **AND** cache entries already rendered before cancellation SHALL be retained

#### Scenario: Idle prewarm yields between messages
- **WHEN** idle prewarm renders multiple messages
- **THEN** it SHALL check for cancellation and yield between each message render
- **AND** SHALL NOT block the main thread for the entire batch duration

### Requirement: Startup prewarm covers expanded scope
The startup prewarm MUST cover at least 4 non-active conversations with at least 8 assistant messages each, up from the previous 2 conversations × 4 messages.

#### Scenario: Startup prewarm covers 4 conversations
- **WHEN** the app launches and bootstrap completes
- **AND** there are at least 4 non-active conversations in the sidebar
- **THEN** the system SHALL prewarm the RenderCache for up to 4 of those conversations

#### Scenario: Startup prewarm renders up to 8 assistant messages per conversation
- **WHEN** startup prewarm processes a conversation with 10+ assistant messages
- **THEN** the system SHALL render and cache the most recent 8 assistant messages

### Requirement: Streaming-complete prewarm caches final assistant content
When a background conversation's streaming request completes, the system MUST prewarm the RenderCache with the final assistant message content.

#### Scenario: Background streaming completion triggers prewarm
- **WHEN** a non-active conversation's streaming request completes successfully
- **THEN** the system SHALL render and cache the final assistant message content at `HushSpacing.chatContentMaxWidth` width and current style

### Requirement: Protection has bounded per-conversation capacity
Each conversation MUST NOT protect more than a configured maximum number of cache entries (P, default 12). When a new protection would exceed this limit, the oldest protected entry for that conversation MUST lose its protection.

#### Scenario: Protection per conversation is bounded
- **WHEN** conversation A already has P=12 protected entries
- **AND** `markProtected` is called for a 13th key for conversation A
- **THEN** the oldest protected entry for conversation A SHALL lose its protection
- **AND** the new key SHALL become protected

#### Scenario: Protection is only set by prewarm paths
- **WHEN** a cell's `configure()` method calls `cachedOutput(for:)` and gets a cache hit
- **THEN** it SHALL NOT call `markProtected`
- **AND** protection SHALL only be set by prewarm completion paths (switch-away, idle, startup, streaming-complete)

### Requirement: Protection lifecycle is tied to scene pool and conversation deletion
Protection MUST be cleared when its owning conversation is evicted from the hot scene pool or deleted by the user. This prevents stale protections from accumulating.

#### Scenario: Pool eviction clears protection
- **WHEN** a conversation's scene is evicted from the hot scene pool
- **THEN** `clearProtection(conversationID:)` SHALL be called for that conversation

#### Scenario: Conversation deletion clears protection
- **WHEN** a user deletes a conversation
- **THEN** `clearProtection(conversationID:)` SHALL be called for that conversation

### Requirement: Window resize invalidates protection for stale widths
When the window is resized, all existing protection entries (keyed at the old width) lose their value. The system MUST clear all protections and re-prewarm at the new width.

#### Scenario: Resize clears all protections
- **WHEN** the window resize stabilizes (debounced 300ms)
- **THEN** `clearAllProtections()` SHALL be called
- **AND** a tail prewarm for active and hot conversations SHALL be triggered at the new width

#### Scenario: Resize does not trigger prewarm during resize drag
- **WHEN** the user is actively dragging the window resize handle
- **THEN** no prewarm SHALL be triggered until the resize stabilizes

### Requirement: All RenderCache and prewarm access runs on @MainActor
All access to RenderCache (read, write, protection operations) and all prewarm rendering MUST execute on `@MainActor` to prevent data races. Prewarm work MUST use cooperative priority (`Task(priority: .utility)`) to avoid blocking user interaction.

#### Scenario: Prewarm executes on @MainActor
- **WHEN** any prewarm path is triggered
- **THEN** the render work SHALL execute on the `@MainActor`
- **AND** SHALL NOT use `Task.detached` or any non-MainActor-isolated execution context

#### Scenario: Prewarm at utility priority yields to user interaction
- **WHEN** prewarm is running and a user-initiated action occurs (typing, clicking, switching)
- **THEN** the user action SHALL be processed without waiting for prewarm to complete
