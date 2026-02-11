## ADDED Requirements

### Requirement: Assistant messages render Markdown as rich text
The system MUST render assistant message content as rich text on macOS 13+ when the content contains Markdown formatting. Rendering MUST preserve readable plain text output when content does not contain Markdown.

#### Scenario: Basic Markdown formatting is displayed
- **WHEN** an assistant message contains Markdown constructs (e.g. headings, emphasis, lists, links, inline code, fenced code blocks)
- **THEN** the system SHALL display the message with corresponding rich formatting instead of showing raw Markdown markers

#### Scenario: Plain text remains readable
- **WHEN** an assistant message contains no Markdown markers
- **THEN** the system SHALL render the content as readable plain text without visual regressions

### Requirement: Code spans and code blocks are readable and preserve content
The system MUST render inline code spans and fenced code blocks in a readable way that preserves the original code content, including whitespace and line breaks.

#### Scenario: Inline code is rendered as code
- **WHEN** an assistant message contains an inline code span
- **THEN** the system SHALL render it in a code style and SHALL preserve the literal characters within the span

#### Scenario: Fenced code blocks preserve whitespace and line breaks
- **WHEN** an assistant message contains a fenced code block
- **THEN** the system SHALL render the code in a readable code-block style and SHALL preserve whitespace and line breaks

### Requirement: Rendering never crashes and degrades gracefully
The system MUST NOT crash due to malformed Markdown, invalid Unicode, or unsupported constructs. When a construct cannot be rendered, the system MUST fall back to a readable representation of the original source.

#### Scenario: Malformed Markdown does not crash
- **WHEN** an assistant message contains malformed Markdown (e.g. unclosed fences, broken tables, unmatched delimiters)
- **THEN** the system SHALL still render a readable message and SHALL NOT crash

#### Scenario: Partial streaming content does not crash
- **WHEN** an assistant message is updated during streaming and the current partial content ends with incomplete constructs (e.g. an unclosed code fence or an unclosed math delimiter)
- **THEN** the system SHALL still render a readable message and SHALL NOT crash

### Requirement: LaTeX math is rendered with safe fallback
The system MUST detect LaTeX math segments delimited by `$...$` (inline) and `$$...$$` (block) and attempt to render them as inline/block math. If math rendering fails or contains unsupported macros, the system MUST fall back to displaying the original LaTeX source in a readable way and MUST keep copy/select behavior intact.

#### Scenario: Common math renders successfully
- **WHEN** an assistant message contains common LaTeX math segments
- **THEN** the system SHALL render them as typeset math content

#### Scenario: Unsupported macro falls back without crashing
- **WHEN** a LaTeX math segment cannot be rendered due to unsupported macros or invalid input
- **THEN** the system SHALL display the original LaTeX source for that segment and SHALL NOT crash

### Requirement: Math delimiter handling is conservative and context-aware
The system MUST apply math delimiter parsing conservatively to avoid misinterpreting non-math text. Math delimiter parsing MUST be disabled inside inline code spans and fenced code blocks. Escaped dollar signs (`\\$`) MUST be treated as literal characters.

#### Scenario: Dollar signs inside inline code are not treated as math
- **WHEN** an assistant message contains `$...$` or `$$...$$` inside an inline code span
- **THEN** the system SHALL render the code span literally without attempting math rendering inside it

#### Scenario: Dollar signs inside fenced code blocks are not treated as math
- **WHEN** an assistant message contains `$...$` or `$$...$$` inside a fenced code block
- **THEN** the system SHALL render the code block literally without attempting math rendering inside it

#### Scenario: Escaped dollar signs are treated as literal
- **WHEN** an assistant message contains an escaped dollar sign (`\\$`) in normal text
- **THEN** the system SHALL render a literal `$` character and SHALL NOT treat it as a math delimiter

#### Scenario: Currency ranges are not misinterpreted as math
- **WHEN** an assistant message contains common currency patterns such as `$10-$20`
- **THEN** the system SHALL render the dollar signs as literal characters and SHALL NOT attempt to typeset “math” for the currency range

#### Scenario: Incomplete math delimiters render literally until complete
- **WHEN** an assistant message contains an opening `$` or `$$` without a matching closing delimiter (common during streaming)
- **THEN** the system SHALL render the delimiter and subsequent text literally until a valid closing delimiter is present

### Requirement: Tables are readable with a fallback strategy
The system MUST provide a readable rendering for Markdown tables. The table rendering MAY be a simplified representation, but it MUST preserve cell content and row/column separation. If a table exceeds available width, the system MUST provide a way to view the full content (e.g. horizontal scrolling or a wrapped monospace fallback).

#### Scenario: Table content remains readable
- **WHEN** an assistant message contains a Markdown table
- **THEN** the system SHALL present the table with visible row/column structure and readable cell content

#### Scenario: Wide table remains accessible
- **WHEN** a rendered table is wider than the available chat content width
- **THEN** the system SHALL still allow the user to access all columns (e.g. via horizontal scroll or fallback formatting)

### Requirement: Rendered output reflows on width changes
The system MUST re-render or reflow assistant message rendering when the available content width changes (e.g. window resize) so text wrapping and table fallbacks remain readable. The system MUST NOT reuse stale cached layout that was computed for a different width.

#### Scenario: Window resize produces width-appropriate rendering
- **WHEN** the available chat content width changes after a message has been rendered
- **THEN** the system SHALL update the rendered output so wrapping/fallbacks match the new width

### Requirement: Streaming updates keep the UI responsive
The system MUST support incremental assistant message updates (streaming) without blocking the UI. Updates MUST produce coherent rendered output (no corrupt formatting) and MUST NOT significantly degrade scrolling responsiveness.

#### Scenario: Partial assistant content updates render coherently
- **WHEN** an assistant message content is updated multiple times during streaming
- **THEN** the system SHALL update the rendered output without corrupting formatting and SHALL NOT crash

#### Scenario: Rapid streaming updates are coalesced and stale renders are canceled
- **WHEN** an assistant message receives many small updates in a short time window
- **THEN** the system SHALL coalesce rendering work to a bounded update rate (e.g. at most one render per configured throttle window) and SHALL ensure stale renders do not apply out-of-order

### Requirement: Rendering caches are bounded to protect memory
The system MUST bound internal rendering caches (message render results and math render results) to avoid unbounded memory growth during long sessions. Cache eviction behavior SHOULD be deterministic to support unit testing.

#### Scenario: Cache entries do not exceed configured capacity
- **WHEN** the system renders more unique messages/formulas than the configured cache capacity
- **THEN** the system SHALL evict older entries and SHALL keep cache size within the configured capacity

### Requirement: Pathological inputs do not cause resource exhaustion
The system MUST protect against pathological assistant content (e.g. extremely long messages or extremely many math segments/tables) by applying guardrails and falling back to a readable representation. The system MUST keep the app responsive and MUST NOT crash due to excessive allocations.

#### Scenario: Too many math segments fall back safely
- **WHEN** an assistant message contains more math segments than the configured maximum
- **THEN** the system SHALL render a readable fallback for the excess segments and SHALL NOT crash

### Requirement: Text selection and copy are scoped to a single message
The system MUST support text selection and copy within a single rendered assistant message. The system MUST NOT require cross-message selection/copy support.

#### Scenario: Selecting within one message works
- **WHEN** the user selects text inside a single assistant message
- **THEN** the system SHALL allow copying the selected text

### Requirement: Rendering is encapsulated behind a cohesive module boundary
Rendering logic (Markdown parsing, LaTeX detection, table fallback) MUST be encapsulated behind a cohesive module boundary with a stable interface so the chat UI can call “render” without directly depending on parsing or math rendering internals.

#### Scenario: Chat UI uses a renderer interface
- **WHEN** the chat UI displays assistant message content
- **THEN** it SHALL invoke a renderer interface to obtain a renderable result rather than inlining parsing logic in SwiftUI views
