## Why

Phase 1 renders Markdown tables as monospace “table blocks” inside the assistant `NSTextView`. This is predictable and low-memory, but wide tables wrap/clamp and quickly become hard to read because columns lose alignment and users cannot easily inspect rightmost columns.

We want an ergonomic, horizontally scrollable table experience while keeping the existing TextKit-based Markdown/LaTeX renderer architecture and its streaming performance guarantees (bounded work, cancellable updates, low view count, and graceful fallback).

## What Changes

- Add an optional Phase 2 table strategy: render Markdown tables as a **single horizontally scrollable attachment view** (one view per table, not per cell).
- Attempt Phase 2 rendering only for **non-streaming** renders; keep Phase 1 monospace table blocks as the streaming path and as the deterministic fallback.
- Keep LaTeX rendering inside table cell text consistent with non-table text (`$...$` / `$$...$$`) using the existing math pipeline and per-message math guardrails.
- Preserve a deterministic fallback to Phase 1 monospace tables when an attachment view cannot/should not be created (e.g., guardrails, API availability, construction failure).
- Ensure selection/copy works within a table attachment. Selection across table and surrounding message text is not required (tables become an independent selectable region).
- Add fixture-driven tests covering attachment-vs-fallback decisions, math-in-cells, width changes, and fallback behavior.

## Goals / Non-Goals

**Goals:**
- Wide tables remain readable (no wrapping inside the table; user can scroll horizontally to inspect columns).
- Low and predictable view count: one attachment view per table, with a per-message attachment cap.
- Streaming remains smooth: no repeated expensive attachment view construction while content is changing.
- Non-fatal failure: any attachment failure deterministically falls back to Phase 1 rendering.
- Styling matches the app theme (dark, app typography/colors).

**Non-Goals:**
- Full GitHub Flavored Markdown table parity (alignment rules, nested block content, etc.).
- Spreadsheet-like interactions (sorting, resizing columns, editable cells).
- Cross-boundary selection/copy between table content and the main message `NSTextView`.
- Perfect column alignment when math attachments render wider than their source text (acceptable for v1).

## UX / Behavior

- A table rendered via attachment appears as a single inline block in the message.
- The table surface:
  - is horizontally scrollable
  - is not vertically scrollable (vertical scrolling continues to scroll the transcript)
  - uses the same monospace table formatting as Phase 1 (row/column separators remain familiar)
- Selection/copy:
  - users can select and copy within the table surface
  - selection does not extend into surrounding message text
  - copy/paste behavior is the standard `NSTextView` behavior for attributed content (rich targets may include attachments; plain-text targets may not preserve attachment visuals)

## Guardrails & Fallback

Tables render as attachments only when **all** are true:

- Rendering pass is **non-streaming** (`MessageRenderInput.isStreaming == false`). While streaming, tables stay in Phase 1 monospace form to avoid thrashing attachment views.
- Attachment APIs are available for the hosting `NSTextView` (TextKit 1 vs TextKit 2 approach confirmed in task 1.1).
- Table is within conservative limits (initial defaults; tune as needed):
  - `maxTableAttachmentsPerMessage = 3`
  - per-table: `maxRows = 80`, `maxColumns = 20`, `maxCells = 1200`
  - per-table: `maxRenderedChars = 20000` (based on the Phase 1 table string before math attachment substitution)

Any guardrail trigger, API unavailability, or failure during attachment creation/measurement must fall back to Phase 1 monospace rendering and emit diagnostics.

## Diagnostics (for Testing + Debugging)

- When Phase 2 attachment rendering is used, emit a diagnostic indicating “table rendered as attachment” so tests can assert attachment-vs-fallback deterministically.
- When Phase 1 fallback rendering is used, continue emitting a “table fallback” diagnostic (and a `guardrailTriggered` diagnostic when the fallback reason is a guardrail).

## Known Limitations

- Table cells are rendered using a conservative “plaintext extraction” strategy (as in Phase 1). Some inline constructs may be flattened or dropped (e.g., links), and tables are not intended to match full GFM fidelity.
- Math segmentation is applied to the flattened table lines; inline code context inside table cells is not preserved as a distinct “code region” for math skipping.
- When a streaming message finalizes, a table may “jump” from Phase 1 monospace rendering to a Phase 2 attachment rendering on the next non-streaming render pass.

## Capabilities

### New Capabilities

- `markdown-table-scroll-attachment`: Render Markdown tables as horizontally scrollable attachments inside the TextKit message renderer, preserving readable cell content (including math) with safe fallbacks.

### Modified Capabilities

<!-- None. This change adds an optional table rendering strategy within the existing renderer module. -->

## Impact

- Renderer: add a table attachment renderer integrated at the Markdown table node conversion boundary (currently `MarkdownToAttributed.renderTable(...)`).
- TextKit hosting: may require enabling view-based text attachments for the assistant `NSTextView` (investigate TextKit 1 vs TextKit 2; keep a safe fallback).
- Testing: new fixtures and unit tests for attachment-vs-fallback decisions, math-in-table-cells behavior, width changes, and deterministic fallback when guardrails trigger.

## Open Questions

- Best attachment implementation on macOS for the current `NSTextView` hosting (TextKit 1 attachment cell vs TextKit 2 `NSTextAttachmentViewProvider`), and whether the host should migrate.
- Whether we should allow attachment rendering during streaming after a debounce (future enhancement), or keep “attachments only when finalized” as a hard rule.
- Whether we need custom copy behavior to guarantee a high-quality plain-text representation when math attachments are present.
