## ADDED Requirements

### Requirement: Render scheduler supports multi-tier conversation priority
The ConversationRenderScheduler MUST support three tiers of conversation priority: active, hot, and cold. Render work for cold conversations MUST be pruned. Render work for hot conversations MUST be accepted but at reduced priority.

#### Scenario: Active conversation work executes at original priority
- **WHEN** render work is enqueued for the active conversation
- **THEN** the scheduler SHALL execute it at the priority specified by the enqueue call

#### Scenario: Hot conversation work executes at demoted priority
- **WHEN** render work is enqueued for a hot (pooled but hidden) conversation with priority `.high`
- **THEN** the scheduler SHALL execute it but at `.visible` priority (demoted one level)

#### Scenario: Cold conversation work is pruned
- **WHEN** render work is enqueued for a conversation that is neither active nor hot
- **THEN** the scheduler SHALL prune (discard) that work item

#### Scenario: Existing cold-prune behavior is preserved
- **WHEN** `setSceneConfiguration` is called with a new active conversation
- **AND** there are queued work items for conversations not in the active or hot set
- **THEN** those work items SHALL be pruned immediately
- **AND** the behavior SHALL be identical to the current single-conversation stale pruning for cold conversations

### Requirement: Scene configuration is set atomically
The scheduler MUST accept a single atomic configuration update specifying the active conversation ID, the set of hot conversation IDs, and the generation for each.

#### Scenario: setSceneConfiguration updates all tiers at once
- **WHEN** `setSceneConfiguration(active: (id, gen), hot: [(id, gen), ...])` is called
- **THEN** the scheduler SHALL update its internal state for active and hot tiers atomically
- **AND** SHALL prune any work items that are now cold

#### Scenario: Generation mismatch within a tier causes stale pruning
- **WHEN** a work item's generation does not match the current generation for its conversation
- **THEN** that work item SHALL be considered stale and pruned
- **AND** this SHALL apply to both active and hot tiers

#### Scenario: setActiveConversation backward compatibility
- **WHEN** `setActiveConversation(conversationID:generation:)` is called
- **THEN** it SHALL behave identically to `setSceneConfiguration(active: (id, gen), hot: [])`
- **AND** all non-active work items SHALL be pruned as cold

### Requirement: Hidden scenes defer UI updates until visible
When a hot (hidden) scene receives message updates from streaming, the system MUST NOT immediately apply UI updates (reloadData). Updates MUST be deferred and batched until the scene becomes visible.

#### Scenario: Hidden scene marks dirty on streaming delta
- **WHEN** a hidden scene's conversation receives a streaming content update
- **THEN** the scene SHALL be marked as needing reload (needsReload = true)
- **AND** SHALL NOT call tableView.reloadData

#### Scenario: Dirty scene reloads on becoming visible
- **WHEN** a scene marked as needing reload becomes the active (visible) scene
- **THEN** the scene SHALL call tableView.reloadData with the latest messages
- **AND** SHALL clear the needsReload flag

#### Scenario: Non-dirty scene does not reload on visibility
- **WHEN** a scene that is NOT marked as needing reload becomes visible
- **THEN** the scene SHALL NOT call tableView.reloadData

### Requirement: SwiftUI update propagation is isolated to active scene
The `HotScenePoolRepresentable.updateNSViewController()` callback MUST only forward state updates to the currently active (visible) scene. Hidden scenes MUST NOT receive `renderConversationState()` calls through the SwiftUI update path.

#### Scenario: SwiftUI body diff only updates active scene
- **WHEN** `updateNSViewController()` is called due to `@Published` state change on `AppContainer`
- **THEN** the `HotScenePoolController` SHALL forward the update only to the active (visible) `ConversationViewController`
- **AND** SHALL NOT call `update(container:)` or `renderConversationState()` on hidden scenes

#### Scenario: Hidden scene receives updates only via internal dirty marking
- **WHEN** a hidden scene's conversation has new messages (via `messagesByConversationId`)
- **THEN** the scene SHALL only be marked `needsReload = true` by the `HotScenePool` message routing logic
- **AND** SHALL NOT be updated by SwiftUI's `updateNSViewController` path

### Requirement: Tail prewarm maintains render cache for hot scenes
The system MUST continuously maintain RenderCache entries for the tail K assistant messages of each hot scene's conversation, where K is a configurable constant.

Scope note: This requirement governs **continuous tail prewarm** behavior for **hot** scenes only. For **cold** conversations, the system MAY still run a one-shot streaming-complete prewarm for the final assistant message as defined in `render-cache-conversation-protection/spec.md`.

#### Scenario: Streaming completion in hot scene triggers tail prewarm
- **WHEN** a hot scene's conversation completes a streaming request
- **THEN** the system SHALL prewarm the RenderCache with the latest K assistant messages of that conversation

#### Scenario: Tail prewarm does not run for cold conversations
- **WHEN** a conversation is not in the hot scene pool
- **THEN** the system SHALL NOT perform continuous tail prewarm for that conversation

#### Scenario: Tail prewarm respects existing cache entries
- **WHEN** tail prewarm runs for a hot scene
- **AND** some of the tail messages are already in RenderCache
- **THEN** the system SHALL only render and cache the missing entries
