## ADDED Requirements

### Requirement: Hot scene pool maintains a bounded set of live conversation views
The system MUST maintain a pool of up to N (default 3) ConversationViewController instances, each bound to a distinct conversation. The pool capacity N MUST be defined as a constant and MUST NOT exceed a hard maximum of 6.

#### Scenario: Pool creates scene on first visit
- **WHEN** a conversation is activated that has no existing scene in the pool
- **AND** the pool has remaining capacity
- **THEN** the system SHALL create a new ConversationViewController for that conversation and add it to the pool

#### Scenario: Pool evicts coldest scene when at capacity
- **WHEN** a conversation is activated that has no existing scene in the pool
- **AND** the pool is at capacity
- **THEN** the system SHALL evict the least-recently-used (coldest) scene from the pool
- **AND** SHALL clean up the evicted scene's view hierarchy and release its resources

#### Scenario: Pool capacity is bounded by constant
- **WHEN** the hot scene pool is initialized
- **THEN** its capacity SHALL equal `RenderConstants.hotScenePoolCapacity`
- **AND** the value SHALL NOT exceed 6

### Requirement: Switching to a pooled conversation uses visibility toggle
When switching to a conversation whose scene already exists in the pool, the system MUST show that scene by toggling visibility, without destroying or recreating the view hierarchy.

#### Scenario: Switch to hot scene is a visibility toggle
- **WHEN** user switches to conversation B which has a live scene in the pool
- **THEN** the current scene's view SHALL be hidden (isHidden = true)
- **AND** conversation B's scene's view SHALL be shown (isHidden = false)
- **AND** the NSTableView SHALL NOT call reloadData for this switch

#### Scenario: Scroll position is preserved across switches
- **WHEN** user scrolls up in conversation A, switches to B, then switches back to A
- **THEN** conversation A's scroll position SHALL be at the same position as before the switch

#### Scenario: Switch to hot scene does not re-trigger cell configure
- **WHEN** user switches to a conversation with an existing hot scene
- **THEN** no MessageTableCellView.prepareForReuse or configure calls SHALL occur for that switch

### Requirement: Switching to a non-pooled conversation creates or recycles a scene
When switching to a conversation not in the pool, the system MUST either create a new scene (if pool has capacity) or evict the coldest scene and reuse the slot.

#### Scenario: Cold conversation switch creates new scene within capacity
- **WHEN** user switches to conversation D which is not in the pool
- **AND** the pool has fewer than N scenes
- **THEN** the system SHALL create a new ConversationViewController for conversation D
- **AND** SHALL apply messages and show it

#### Scenario: Cold conversation switch recycles at capacity
- **WHEN** user switches to conversation D which is not in the pool
- **AND** the pool is at capacity N
- **THEN** the system SHALL remove the least-recently-used scene
- **AND** SHALL create a new scene for conversation D

### Requirement: Evicted scenes release resources cleanly
When a scene is evicted from the pool, its resources MUST be released without leaving dangling references or orphaned subscriptions.

#### Scenario: Evicted scene's view is removed from hierarchy
- **WHEN** a scene is evicted from the hot scene pool
- **THEN** its NSViewController SHALL be removed from the parent controller
- **AND** its view SHALL be removed from the superview

#### Scenario: Evicted scene's render controllers are cancelled
- **WHEN** a scene is evicted from the hot scene pool
- **THEN** all MessageTableCellView instances in the evicted scene's table view SHALL have their render controllers cancelled via prepareForReuse semantics

#### Scenario: Evicting a scene with active background streaming does not affect the stream
- **WHEN** a scene is evicted whose conversation has an active streaming request
- **THEN** the streaming request SHALL continue operating
- **AND** streaming deltas SHALL continue writing to messagesByConversationId
- **AND** switching back to that conversation SHALL display the latest messages

### Requirement: Hot scene pool can be disabled via feature flag
The hot scene pool MUST be disableable via environment variable, falling back to single-VC behavior.

#### Scenario: Feature flag disables pool
- **WHEN** environment variable `HUSH_HOT_SCENE_POOL` is set to "0" or "false"
- **THEN** the system SHALL use a single ConversationViewController (current behavior)
- **AND** SHALL NOT create a pool

#### Scenario: Feature flag absent defaults to pool enabled
- **WHEN** environment variable `HUSH_HOT_SCENE_POOL` is not set
- **THEN** the system SHALL use the hot scene pool

#### Scenario: Feature flag is read once at launch
- **WHEN** the app launches
- **THEN** the feature flag value SHALL be read once and cached as a `static let`
- **AND** changing the environment variable after launch SHALL have no effect

### Requirement: Empty conversations are deprioritized in pool eviction
When the pool needs to evict a scene, empty conversations (0 messages) SHOULD be evicted before non-empty conversations, regardless of LRU order.

#### Scenario: Empty conversation scene is evicted first
- **WHEN** the pool is at capacity and must evict
- **AND** one scene has 0 messages and another has messages but is least-recently-used
- **THEN** the system SHALL evict the empty conversation scene first

#### Scenario: Multiple empty scenes evict by LRU among themselves
- **WHEN** the pool has multiple empty conversation scenes
- **AND** eviction is needed
- **THEN** the system SHALL evict the least-recently-used among the empty scenes
