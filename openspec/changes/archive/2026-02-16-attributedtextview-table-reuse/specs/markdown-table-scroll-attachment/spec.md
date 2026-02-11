## ADDED Requirements

### Requirement: Table attachment host should reuse subviews across updates
The system SHALL reuse existing `TableScrollContainer` subviews within the same message host when table attachment identity remains stable, instead of removing and recreating all table subviews on each update.

#### Scenario: Repeated update reuses table subview instance
- **WHEN** a rendered message is updated with the same table attachments and ordering
- **THEN** the host SHALL keep and reposition existing table subviews rather than recreating them

### Requirement: Horizontal scroll position should persist across non-content redraws
The system SHALL preserve user horizontal scroll offset for reused table attachment subviews during redraws, and SHALL clamp offset when viewport width changes make the previous offset invalid.

#### Scenario: Preserve offset on same-width redraw
- **WHEN** a user scrolls a wide table horizontally and the message host redraws without content identity change
- **THEN** the table SHALL retain the previous horizontal offset

#### Scenario: Clamp offset on wider viewport redraw
- **WHEN** a user scrolls a wide table horizontally and then the viewport widens
- **THEN** the table SHALL clamp the previous offset to the new valid range and SHALL NOT reset unexpectedly to an unrelated value

### Requirement: Host should remove stale table subviews
The system SHALL remove table subviews that are no longer present in the latest rendered attachment set.

#### Scenario: Content changes from table to non-table
- **WHEN** a message previously containing table attachments updates to content without table attachments
- **THEN** the host SHALL remove stale `TableScrollContainer` subviews
