## ADDED Requirements

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
- **WHEN** a Markdown table cell contains common LaTeX math segments such as `$0$`, `$\\pi/2$`, `$\\sqrt{3}/2$`, or `$0^\\circ$`
- **THEN** the system SHALL render those segments as math (or a readable math fallback) and SHALL NOT show raw dollar delimiters in the rendered output

### Requirement: Horizontal scrolling exposes all columns of wide tables
The system MUST allow the user to access all columns of a wide table.

#### Scenario: Wide table can be fully viewed
- **WHEN** a rendered Markdown table exceeds the available chat content width
- **THEN** the user SHALL be able to scroll horizontally to view all columns

