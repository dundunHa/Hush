## Context

Hush renders assistant messages via a per-message `NSTextView` hosted in SwiftUI (`AttributedTextView`). Markdown is parsed into an AST (`swift-markdown`) and converted into an `NSAttributedString` by `HushRendering/MarkdownToAttributed`. LaTeX math segments (`$...$` / `$$...$$`) are segmented (`MathSegmenter`) and rendered as `NSTextAttachment` images via SwiftMath (`MathRenderer`), with guardrails and diagnostics.

Phase 1 table rendering intentionally uses a readable monospace fallback (`TableRenderer`) that becomes plain text inside the same `NSTextView`. This satisfies correctness and safety goals, but wide tables are ergonomically poor because they wrap/clamp to message width and lose column readability.

This change adds an optional Phase 2 table strategy: render tables as a horizontally scrollable attachment view (one view per table, not per cell), while preserving safe fallbacks and streaming performance.

Constraints carried forward from the Phase 1 renderer:
- Must remain responsive during streaming (bounded work, cancellable rendering).
- Failures must degrade gracefully (no crashes, readable fallback).
- Dark theme + app-defined typography/colors.
- Avoid a SwiftUI view tree per table cell (keep view count low and predictable).

## Goals / Non-Goals

**Goals:**
- Render Markdown tables as horizontally scrollable content when using the Phase 2 strategy.
- Keep table cell content readable and preserve row/column structure.
- Preserve LaTeX rendering inside table cells using the same delimiter/guardrail rules as normal text.
- Keep selection/copy working within a table.
- Provide a deterministic fallback path back to the Phase 1 monospace table block.

**Non-Goals:**
- Full GitHub Flavored Markdown table parity (alignment rules, nested block content, etc.).
- Spreadsheet-like interactions (sorting, resizing columns, editable cells).
- Cross-region selection that spans table content and surrounding message text.
- Perfect visual column alignment when math attachments produce widths larger than their source text (may be improved later).

## Decisions

### 1) Tables Become an Independent Selectable Region

**Decision:** When rendered via a table attachment view, the table is treated as an independent selection/copy surface. Users can select/copy within the table, but selection does not need to extend from message text into the table or vice versa.

**Why:**
- Keeps the attachment implementation simple and robust.
- Matches the existing product constraint that selection/copy is scoped to a single message, while acknowledging that sub-region selection continuity is not a hard requirement.
- Avoids complex text-system bridging work that would be required to support seamless cross-boundary selection.

**Alternatives considered:**
- Preserve continuous selection by keeping tables as plain text in the main `NSTextView`. Rejected because it does not solve the wide-table ergonomics problem.
- Render the entire message as a single custom layout system. Rejected due to complexity and risk to streaming performance.

### 2) Implement Horizontal Scroll as a View-Based Text Attachment (One View per Table)

**Decision:** Represent each table as a single text attachment that provides an AppKit view containing:
- An `NSScrollView` with horizontal scrolling enabled and vertical scrolling disabled.
- A nested, non-editable, selectable `NSTextView` to display the rendered table content.

The nested `NSTextView` displays the same monospace fallback text produced by `TableRenderer`, but configured to avoid line wrapping so wide tables remain aligned and readable.

**Why:**
- Maintains low view count (1 attachment view per table).
- Reuses existing Phase 1 table formatting logic and styling.
- Selection/copy inside the table works “for free” via the nested `NSTextView`.

**Alternatives considered:**
- Render the table as an image attachment. Rejected because it breaks selection/copy and accessibility.
- Build a custom NSView grid with one view per cell. Rejected due to view explosion risk and increased layout overhead.

### 3) Preserve a Conservative Fallback Path

**Decision:** Table attachments are optional and guarded:
- If a table is too large/complex (configurable caps), render as Phase 1 monospace fallback inside the main message `NSTextView`.
- If attachment construction fails for any reason, fall back to Phase 1 rendering and emit diagnostics.
- While streaming (`MessageRenderInput.isStreaming == true`), render tables using Phase 1 monospace blocks to avoid attachment view thrash; attachment rendering is attempted on a subsequent non-streaming render pass.

**Why:**
- Matches the renderer’s “never crash” and “guardrails first” philosophy.
- Keeps streaming stable even when partial content temporarily produces malformed tables.

### 4) Math-in-Cells Uses the Existing Math Pipeline

**Decision:** The table content shown in the attachment uses the same math segmentation + rendering behavior as normal text:
- `$...$` (inline, single-line)
- `$$...$$` (block, may span newlines)
- ignored in code
- `\\$` is literal
- currency patterns remain literal

Implementation-wise, the attachment’s nested `NSTextView` receives an attributed table string where `$...$` segments have already been replaced by math attachments (or a readable fallback on failure).

**Note:** table rendering starts from a flattened Phase 1 “monospace table string”. Inline code contexts inside table cells are not preserved as distinct “code regions” for math skipping; math segmentation is applied to the flattened table lines.

## Guardrails (Initial Defaults)

Attachment rendering is attempted only when all are true:
- Render pass is non-streaming.
- Attachment APIs are available for the host `NSTextView` (TextKit 1 vs TextKit 2).
- Table is within limits:
  - `maxTableAttachmentsPerMessage = 3`
  - per-table: `maxRows = 80`, `maxColumns = 20`, `maxCells = 1200`
  - per-table: `maxRenderedChars = 20000` (based on the Phase 1 table string before math attachment substitution)

Any guardrail trigger, API unavailability, or construction/measurement failure deterministically falls back to Phase 1 monospace rendering and emits diagnostics.

Diagnostics intent:
- Emit a “table attachment” diagnostic when Phase 2 attachment rendering is used.
- Emit a “table fallback” diagnostic when Phase 1 rendering is used (and `guardrailTriggered` when the reason is a guardrail).

## Risks / Trade-offs

- **[Risk] Selection continuity regression** → **Mitigation:** explicitly accept “independent selection surface” for tables; ensure table selection/copy is reliable and add tests for copy behavior.
- **[Risk] TextKit 1 vs TextKit 2 attachment-view APIs** → **Mitigation:** keep the attachment surface behind a single renderer boundary; retain Phase 1 fallback; spike a minimal attachment view provider early and keep it guarded by runtime checks.
- **[Risk] Gesture conflicts (horizontal scroll inside vertical transcript scroll)** → **Mitigation:** disable vertical scrolling in the table scroll view; rely on horizontal scroll wheel/trackpad deltas; ensure table view consumes horizontal deltas only.
- **[Risk] Memory/perf increase for many tables** → **Mitigation:** one view per table only; keep nested text views lightweight; add guardrails to fall back for pathological cases.
- **[Risk] Column misalignment with rendered math attachments** → **Mitigation:** accept for Phase 2; track as a follow-up improvement (true rendered-width based layout).
- **[Risk] “Jump” on stream finalization** (table switches from monospace fallback to attachment on the first non-streaming render pass) → **Mitigation:** treat as acceptable for v1; keep the swap deterministic and covered by tests.
