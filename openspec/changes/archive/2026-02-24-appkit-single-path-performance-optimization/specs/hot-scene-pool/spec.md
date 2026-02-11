## ADDED Requirements

### Requirement: Hot scene pool is mandatory for chat conversation rendering
The system MUST use Hot Scene Pool as the only conversation view host in chat rendering and MUST NOT fall back to a single-view-controller route.

#### Scenario: Chat rendering initializes with pool host
- **WHEN** a chat conversation is displayed
- **THEN** the system SHALL initialize or reuse a pooled conversation scene
- **AND** SHALL apply updates through pool-managed scenes only

#### Scenario: Pool lifecycle is preserved without fallback mode
- **WHEN** users switch between conversations
- **THEN** the system SHALL preserve existing pool semantics for hot hit, cold miss, and eviction
- **AND** SHALL not route switches through a non-pool single controller mode

## REMOVED Requirements

### Requirement: Hot scene pool can be disabled via feature flag
**Reason**: Chat rendering is standardized to a single AppKit path to remove route divergence and reduce maintenance overhead.
**Migration**: Remove reliance on `HUSH_HOT_SCENE_POOL` for route selection. Tests and scripts should validate only pool-based behavior.
