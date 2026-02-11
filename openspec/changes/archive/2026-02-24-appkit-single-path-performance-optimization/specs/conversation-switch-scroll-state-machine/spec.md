## ADDED Requirements

### Requirement: Single-path chat routing preserves switch scroll semantics
After migrating to AppKit single-path chat routing, the system MUST preserve conversation switch auto-scroll and tail-follow semantics.

#### Scenario: Switch to populated conversation still scrolls to bottom
- **WHEN** user switches to a conversation containing messages
- **THEN** the system SHALL keep bottom-scroll behavior consistent with existing switch semantics
- **AND** SHALL render the latest tail content as the visible target

#### Scenario: Ongoing streaming conversation keeps tail-follow behavior
- **WHEN** user switches to a conversation that is currently streaming
- **THEN** the system SHALL continue tail-follow behavior for streamed content
- **AND** SHALL not regress to stale-anchor behavior due to route consolidation
