# HushRendering

Two-phase markdown render pipeline: Phase 1 monospace fallback (instant), Phase 2 rich NSAttributedString (async). Handles code blocks, LaTeX math, tables, and streaming content. Row height caching for AppKit table view performance.

## Structure

```
RenderController.swift                # @MainActor per-message render lifecycle, throttled coalescing
ConversationRenderScheduler.swift     # Serial scheduler with priority queue (high/visible/deferred/idle)
MarkdownToAttributed.swift            # Markdown AST -> NSAttributedString conversion (776 lines)
MathSegmenter.swift                   # Extracts LaTeX segments from markdown text
MathRenderer.swift                    # Renders LaTeX -> images via SwiftMath
MathRenderCache.swift                 # 128-entry LRU cache for rendered math
TableRenderer.swift                   # Markdown table -> monospace NSAttributedString
RenderCache.swift                     # 256-entry LRU cache for rendered attributed strings
RowHeightCache.swift                  # Per-message row height cache for NSTableView (width-keyed)
RenderConstants.swift                 # Render pipeline tunables (coalescing intervals, cache sizes)
RenderStyle.swift                     # Font/color/spacing tokens for render output
AttributedStringKeys.swift            # Custom NSAttributedString key definitions
MessageContentRenderer.swift          # Orchestrates content rendering (text + images)
MessageRenderHint.swift               # Hints for render priority/visibility
MessageRenderInput.swift              # Input model for render pipeline
MessageRenderOutput.swift             # Output model (attributed string + metadata)
MessageRenderRuntime.swift            # Per-message render state machine
CodeBlockHighlighter.swift            # Syntax highlighting for fenced code blocks
```

## Where to Look

| Task | File |
|------|------|
| Modify render output format | `MarkdownToAttributed.swift` |
| Change render scheduling/priority | `ConversationRenderScheduler.swift` |
| Adjust streaming coalescing | `RenderController.swift` |
| Add new LaTeX handling | `MathSegmenter.swift` + `MathRenderer.swift` |
| Cache tuning | `RenderCache.swift` (256) / `MathRenderCache.swift` (128) / `RowHeightCache.swift` |
| Table rendering | `TableRenderer.swift` |
| Row height for AppKit table | `RowHeightCache.swift` — invalidated on width change or content update |
| Render style tokens | `RenderStyle.swift` — consumed by `MarkdownToAttributed` |
| Custom attributed string keys | `AttributedStringKeys.swift` |

## Conventions

- **Two-phase always**: Phase 1 monospace fallback renders first (instant), Phase 2 rich markdown follows async. Never skip Phase 1.
- **RenderController is per-message**: One controller per `ChatMessage`. Owned by the view layer.
- **Coalescing**: During streaming, `RenderController` throttles updates to avoid excessive re-renders.
- **Priority queue**: `ConversationRenderScheduler` uses budget intervals — visible messages get `high`, off-screen get `deferred`/`idle`.
- **Cache before clear**: Always apply cached output immediately — never clear `currentOutput` before replacement is ready.
- **RowHeightCache**: Keyed by message ID + table width. Invalidated on resize via `ResizeCacheCleanup`. Prevents layout thrashing.
- **RenderStyle**: Consumed by `MarkdownToAttributed` and varies by `ConversationSurfaceStyle` (main window vs Quick Bar).

## Anti-Patterns

- **Never pass dollar signs inside code spans/blocks to MathSegmenter** — code-fenced `$` is literal, not LaTeX.
- **Never clear currentOutput before replacement ready** — user sees blank flash.
- **Never skip Phase 1 monospace fallback** — it's the instant-feedback contract during streaming.
- **Never render synchronously on main thread for long content** — always use `ConversationRenderScheduler` for Phase 2.
