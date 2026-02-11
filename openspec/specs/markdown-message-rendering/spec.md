# Markdown Message Rendering

## Purpose
The purpose of this capability is to provide rich text rendering of Markdown content (including LaTeX math and tables) in assistant messages while ensuring performance, safety, and a responsive streaming experience.

## Requirements

### Requirement: Streaming render optimization preserves responsiveness without changing render semantics
The system MUST reduce redundant streaming render work and main-thread layout churn while preserving existing Markdown, LaTeX, and table rendering semantics.

#### Scenario: Streaming updates avoid full-list relayout bursts
- **WHEN** streaming assistant content updates arrive for an existing message row
- **THEN** the system SHALL update only the necessary row rendering path where safe
- **AND** SHALL avoid unconditional full-list refresh on every streaming tick

#### Scenario: Optimized path preserves rendered output behavior
- **WHEN** performance optimizations are applied to streaming render scheduling
- **THEN** rendered output SHALL remain behaviorally consistent with existing Markdown/LaTeX/table contracts
- **AND** fallback behavior SHALL remain available when optimization preconditions are not met

### Requirement: Prefetch-style prewarm improves near-viewport render readiness
The system MUST support prewarming of near-viewport assistant rows so that entering viewport rows have high cache-hit probability.

#### Scenario: Near-viewport row is prewarmed before visible
- **WHEN** scroll telemetry indicates rows are approaching the visible window
- **THEN** the system SHALL schedule low-priority prewarm for eligible non-streaming assistant rows
- **AND** SHALL skip rows that are already cached

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

#### Scenario: Code blocks provide one-click copy
- **WHEN** an assistant message contains a fenced code block
- **THEN** the system SHALL provide a one-click copy affordance for the code block content
- **AND** the copied text SHALL include only the code content (not any header or language label)

### Requirement: Rendering never crashes and degrades gracefully
The system MUST NOT crash due to malformed Markdown, invalid Unicode, or unsupported constructs. When a construct cannot be rendered, the system MUST fall back to a readable representation of the original source. During dual-track streaming, fast-track plain text updates MUST NOT interfere with slow-track rich rendering. The RenderController's own `streamingCoalesceInterval` SHALL remain at 50ms (unchanged); the 200ms throttle is applied only at the RequestCoordinator input layer.

#### Scenario: Malformed Markdown does not crash
- **WHEN** an assistant message contains malformed Markdown (e.g. unclosed fences, broken tables, unmatched delimiters)
- **THEN** the system SHALL still render a readable message and SHALL NOT crash

#### Scenario: Partial streaming content does not crash
- **WHEN** an assistant message is updated during streaming and the current partial content ends with incomplete constructs (e.g. an unclosed code fence or an unclosed math delimiter)
- **THEN** the system SHALL still render a readable message and SHALL NOT crash

#### Scenario: RenderController coalesce interval unchanged
- **WHEN** a streaming render request arrives at RenderController
- **THEN** RenderController SHALL coalesce using its existing 50ms `streamingCoalesceInterval`
- **AND** this interval SHALL NOT be modified by the dual-track change

#### Scenario: Slow-track rich render replaces fast-track plain text
- **WHEN** the slow-track triggers cell.configure during streaming
- **AND** the RenderController completes a rich render
- **THEN** the rendered rich output SHALL replace any fast-track plain text currently displayed via the Combine sink
- **AND** no visual glitch or crash SHALL occur

#### Scenario: Fast-track plain text does not block slow-track rich render
- **WHEN** the fast-track has set plain text on the cell body label
- **AND** the slow-track triggers a rich render via RenderController
- **THEN** the RenderController's Combine sink SHALL overwrite the plain text with the rich attributed string
- **AND** the sink callback SHALL verify the render result matches the current message (fingerprint/messageID guard)

#### Scenario: Configure respects anti-regression during streaming
- **WHEN** slow-track's cell.configure Phase 1 runs during streaming
- **AND** the incoming model content is shorter than what fast-track has already displayed (`content.count < streamingDisplayedLength`)
- **AND** both current and incoming `isStreaming` are true
- **THEN** the Phase 1 plain text write SHALL be skipped
- **AND** RenderController SHALL still be triggered for rich rendering

#### Scenario: Configure allows final-state overwrite
- **WHEN** slow-track's cell.configure runs with `isStreaming == false`
- **THEN** the Phase 1 plain text write SHALL proceed unconditionally
- **AND** `streamingDisplayedLength` SHALL be reset to 0

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
The system MUST bound internal rendering caches (message render results and math render results) to avoid unbounded memory growth during long sessions. Cache eviction behavior MUST be deterministic to support unit testing. The message render cache MUST support conversation-aware eviction protection so that recently-visited conversations' render results are not prematurely evicted by less relevant entries.

#### Scenario: Cache entries do not exceed configured capacity
- **WHEN** the system renders more unique messages/formulas than the configured cache capacity
- **THEN** the system SHALL evict older entries and SHALL keep cache size within the configured capacity

#### Scenario: Protected entries are evicted only after unprotected entries
- **WHEN** the cache is at capacity and needs to evict
- **AND** both protected and unprotected entries exist
- **THEN** the system SHALL evict the least-recently-used unprotected entry first

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

### Requirement: Long non-streaming assistant messages should support progressive rendering
The system SHALL avoid blocking the switch frame for long non-streaming assistant messages when no cached render output exists. In this case, it SHALL first present readable fallback text and then asynchronously apply rich rendered output.

#### Scenario: Long message cache miss renders progressively
- **WHEN** an assistant message longer than the configured progressive threshold is displayed in non-streaming mode and no cached render output is available
- **THEN** the system SHALL display readable fallback text immediately and SHALL apply rich rendering asynchronously without crashing

#### Scenario: High-priority cache hit renders immediately
- **WHEN** an assistant message longer than the configured progressive threshold is displayed in non-streaming mode with cached render output available and its priority is high (within the latest N messages)
- **THEN** the system SHALL apply rich rendering immediately

#### Scenario: Non-critical cache hit is queued to avoid switch-time burst
- **WHEN** an assistant message has cached render output available but its priority is not high (visible, deferred, or idle)
- **THEN** the system SHALL enqueue the cached output through the render scheduler to avoid bursty main-thread layout during conversation switches

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

### Requirement: Render scheduling should deduplicate identical requests
The system SHALL deduplicate repeated render requests with identical input fingerprint (content, width, style, streaming flag) to reduce redundant work during rapid state changes.

#### Scenario: Duplicate render request is ignored
- **WHEN** a render request arrives with the same fingerprint as the most recent pending/applied request
- **THEN** the controller SHALL skip redundant render scheduling

### Requirement: Non-streaming rich rendering should prioritize latest and visible assistant messages
The system SHALL schedule non-streaming assistant rich renders by conversation-local priority to avoid blocking the switch frame.

#### Scenario: Latest three assistant messages are rendered first
- **WHEN** a conversation switch triggers multiple non-streaming assistant cache misses
- **THEN** assistant messages with `rankFromLatest < 3` SHALL be processed before lower-priority items

#### Scenario: Visible assistant messages are promoted over offscreen deferred work
- **WHEN** an assistant message enters the viewport while deferred/offscreen work exists
- **THEN** the visible message SHALL be processed first according to the priority mapping

#### Scenario: Offscreen idle work respects delay budget
- **WHEN** an assistant message is offscreen and outside the near-latest window
- **THEN** its rich render work SHALL not execute earlier than the configured idle delay

### Requirement: Conversation switch generations should prevent stale rich apply
The system SHALL isolate queued non-streaming render work by conversation switch generation so stale results cannot overwrite current conversation UI.

#### Scenario: Old generation render callback is dropped
- **WHEN** queued work from an older conversation generation completes after a new generation became active
- **THEN** the callback SHALL be ignored and must not update current output
