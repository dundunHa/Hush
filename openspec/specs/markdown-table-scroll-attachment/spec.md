# Markdown Table Scroll Attachment

## Purpose
The purpose of this capability is to render Markdown tables as horizontally scrollable attachment views within assistant messages. This improves the readability of wide tables by avoiding row wrapping while maintaining safe fallbacks to monospace blocks and preserving streaming performance.

## Requirements

### Requirement: Markdown tables render as horizontally scrollable attachments
The system SHALL render Markdown tables as a horizontally scrollable table attachment view inside assistant messages when the table is well-formed and within renderer guardrails. If a table attachment view cannot be created, the system MUST fall back to a readable monospace table block.

#### Scenario: Table renders as scrollable attachment
- **WHEN** an assistant message contains a Markdown table within guardrails
- **THEN** the system SHALL display the table in a horizontally scrollable surface without wrapping table rows to the message width

#### Scenario: Attachment failure falls back to monospace block
- **WHEN** a table attachment cannot be created for a Markdown table (e.g., due to guardrails or runtime failure)
- **THEN** the system MUST render the table as a readable monospace table block and MUST preserve cell content

### Requirement: Table attachment supports selection and copy within the table
The table attachment view MUST allow users to select table text and copy it to the clipboard.

#### Scenario: Selecting within table works
- **WHEN** the user selects text within a rendered table attachment
- **THEN** the system SHALL allow copying the selected text

### Requirement: Table attachment preserves row and column structure
The table attachment rendering MUST preserve cell content and visible row/column separation.

#### Scenario: Row and column separators are visible
- **WHEN** a Markdown table is rendered as an attachment
- **THEN** the rendering SHALL include visible row and column separation and SHALL keep header and data rows readable

### Requirement: LaTeX math in table cells is rendered consistently
The system MUST detect and render LaTeX math segments inside table cell text using the same delimiter and guardrail rules as normal text.

#### Scenario: Common formulas inside table cells render
- **WHEN** a Markdown table cell contains common LaTeX math segments such as `$0$`, `$\pi/2$`, `$\sqrt{3}/2$`, or `$0^\circ$`
- **THEN** the system SHALL render those segments as math (or a readable math fallback) and SHALL NOT show raw dollar delimiters in the rendered output

### Requirement: Horizontal scrolling exposes all columns of wide tables
The system MUST allow the user to access all columns of a wide table.

#### Scenario: Wide table can be fully viewed
- **WHEN** a rendered Markdown table exceeds the available chat content width
- **THEN** the user SHALL be able to scroll horizontally to view all columns

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
