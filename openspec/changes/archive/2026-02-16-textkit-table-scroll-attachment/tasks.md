## 1. Investigation / Feasibility

- [x] 1.1 Confirm the AppKit/TextKit API approach for view-based table attachments in `NSTextView` (TextKit 1 vs TextKit 2) and document any required host changes
- [x] 1.2 Define concrete guardrails for "too large/complex table" that triggers fallback (rows/cols/cells/total chars/attachment count) and confirm streaming behavior
  - Proposed defaults: `maxTableAttachmentsPerMessage = 3`; per-table `maxRows = 80`, `maxColumns = 20`, `maxCells = 1200`, `maxRenderedChars = 20000`
  - Streaming rule: while `MessageRenderInput.isStreaming == true`, render tables as Phase 1 monospace blocks; attempt attachment rendering on a subsequent non-streaming render pass

## 2. Table Attachment Rendering

- [x] 2.1 Add a table attachment type that represents a single table rendered as a horizontally scrollable surface (one view per table)
- [x] 2.2 Render the existing monospace table fallback content into the attachment view without line wrapping, preserving visible row/column separators
- [x] 2.3 Ensure LaTeX math inside table cell text is rendered using the existing math pipeline (or falls back safely) before inserting into the attachment view
- [x] 2.4 Integrate attachment rendering at the Markdown table node boundary (`MarkdownToAttributed.renderTable(...)`) with diagnostics and safe fallback to Phase 1 table blocks

## 3. Interaction & Layout

- [x] 3.1 Ensure the table attachment supports horizontal scrolling while preventing nested vertical scrolling from fighting the transcript scroll
- [x] 3.2 Ensure selection/copy works within the table attachment's content surface (and decide whether custom copy behavior is needed for high-quality plain-text paste targets)
- [x] 3.3 Ensure width changes re-render correctly and the attachment view's visible width matches the available chat content width

## 4. Tests

- [x] 4.1 Add fixtures for wide tables and tables-with-math that exercise attachment rendering
- [x] 4.2 Add renderer tests that assert tables render via attachment when within guardrails (and fall back when not), ideally via explicit diagnostics (attachment vs fallback)
- [x] 4.3 Add tests that math-in-table-cells does not leave raw `$...$` markers in the rendered output (attachment and fallback paths)
- [x] 4.4 Add tests for deterministic fallback when guardrails trigger (pathological table size/shape)

## 5. Verification

- [x] 5.1 Run `make test` and confirm all new tests pass
- [x] 5.2 Manual smoke test via `make run` to validate horizontal scrolling, selection/copy within the table, and graceful fallback behavior
