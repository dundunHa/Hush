## Context

Hush is a macOS 13+ SwiftUI LLM chat client. The chat transcript is currently rendered as a `ScrollView` with a `LazyVStack`, and each `ChatMessage` body is displayed as plain SwiftUI `Text`. Assistant messages are frequently Markdown-like (lists, code, tables) and may include LaTeX math. Assistant output also updates incrementally during streaming, which increases the risk of UI jank if rendering work happens on the main thread or if the SwiftUI view tree becomes too large.

The product goals for this change are:
- Smooth scrolling and interaction under long assistant responses and streaming updates
- Low and predictable memory usage
- High perceived quality of rendered output (without chasing full GitHub / MathJax parity)
- A cohesive rendering module boundary so future strategy changes only require editing the renderer (not the chat UI)

Current UX constraints:
- Copy/selection is currently scoped to a single message (cross-message selection/copy is not required)
- The user bubble UI can remain for user messages; assistant output may be rendered without a bubble for readability
- Dark theme and app-defined typography/colors. The renderer SHOULD operate on AppKit-friendly style inputs (e.g. `NSFont`/`NSColor`) so it can avoid importing SwiftUI; the SwiftUI layer can adapt `HushTypography`/`HushColors` into a renderer style snapshot.

## Goals / Non-Goals

**Goals:**
- Render assistant message content as rich text based on Markdown, with readable table fallback support.
- Render common LaTeX math segments (`$...$`, `$$...$$`) with a native renderer and caching; failures degrade gracefully with no crashes.
- Keep the UI responsive during streaming by supporting incremental updates with cancellation and throttling.
- Encapsulate parsing + rendering into a cohesive module with a stable interface used by the chat UI.
- Add core unit tests covering the renderer’s parsing, segmentation (Markdown/LaTeX), fallback behavior, and caching keys.

**Non-Goals:**
- Full GitHub Flavored Markdown parity (especially edge-case table rules and extensions).
- MathJax-level LaTeX macro coverage.
- Cross-message selection/copy or transcript-wide editing.
- A full HTML/WebView-based rendering stack.

## Decisions

### 1) Use TextKit (NSTextView / TextKit 2) as the assistant rendering surface (Phase 1: per-message host)

**Decision:** Render assistant content in a dedicated `NSTextView` hosted in SwiftUI via `NSViewRepresentable`, one per assistant message.

**Why:**
- TextKit is optimized for text layout and drawing, reducing SwiftUI subview counts and layout work.
- Per-message `NSTextView` naturally enforces “single message selection/copy only”.
- This minimizes disruption: the existing `ScrollView + LazyVStack` transcript and scrolling logic remain intact.

**Alternatives considered:**
- Pure SwiftUI Markdown → many subviews: risk of view-tree explosion and layout overhead for long content.
- Single transcript `NSTextView`: best theoretical performance, but higher implementation complexity (message layout, anchors, per-message interactions) and harder incremental adoption.

**Future path:** If per-message `NSTextView` count becomes a memory bottleneck in very long chats, we can introduce a transcript host later (assistant-only or full transcript) while keeping the renderer API stable.

### 2) Encapsulate rendering behind a single cohesive renderer module

**Decision:** Introduce a renderer module (e.g. `Hush/HushRendering`) that owns:
- Markdown parsing
- LaTeX detection and attachment insertion
- Table fallback formatting
- Theme mapping (fonts/colors)
- Caching + streaming update policy

Chat UI code only calls a stable API (e.g. `render(input:) -> RenderOutput`) and does not directly depend on parser/math renderer types.

**Why:**
- Enables future strategy changes (e.g. transcript host, different table strategy) without rewriting `MessageBubble`/chat views.
- Localizes performance and memory tuning to a single area.

**Alternative considered:** Inline parsing/rendering logic in views. Rejected due to coupling and repetitive work across UI.

**Proposed API shape (sketch):**
- `MessageRenderInput`: `content`, `availableWidth`, `isStreaming`, and a theme/style snapshot (fonts/colors/scales).
- `MessageRenderOutput`: an `NSAttributedString` for display, `plainText` for diagnostics/copy fallbacks, and `diagnostics` for “graceful failure” reporting.

**Module boundary intent:**
- The core renderer SHOULD avoid importing SwiftUI (AppKit + Foundation only). SwiftUI hosting (`NSViewRepresentable`) lives in the chat views layer.

**Layering inside the module:**
- Parsing/segmentation SHOULD produce a lightweight, testable intermediate representation (IR) first.
- The IR is then converted into attributed content + attachments.
- Streaming scheduling (throttle/coalesce) SHOULD be separated from pure parsing to keep the renderer deterministic and testable.

### 3) Markdown parsing: AST-based parser suitable for common GFM output

**Decision:** Use an AST-based Markdown parser package (e.g. `swift-markdown`) and transform nodes into attributed text runs.

**Why:**
- System `AttributedString(markdown:)` is convenient but does not reliably cover tables and many chat-oriented constructs.
- AST gives control to implement “readable fallback” for complex nodes (tables) without building SwiftUI subview trees.

**Alternatives considered:**
- `MarkdownUI`: fast to integrate but renders as SwiftUI views, increasing view count for long content.
- HTML rendering: heavier stack and less predictable memory footprint.

### 4) LaTeX math: native rendering via attachments with strong caching and graceful fallback

**Decision:** Use a native LaTeX renderer (e.g. SwiftMath) to render math segments into attachments inserted into the attributed content. Maintain a formula cache keyed by `(latex, fontSize, color, maxWidth, displayMode)` and fall back to original source on failure.

**Why:**
- Meets “common formulas 100%, complex macros ~80%” with a predictable runtime cost.
- Avoids always-on JS/WebView memory overhead.
- Attachment approach keeps layout inside TextKit.

**Alternatives considered:**
- JSCore/MathJax fallback: better macro coverage, but introduces a heavier runtime and a more complex caching/sandbox story. Not aligned with “worth it” constraint.

### 5) Tables: readable fallback first, upgradeable later

**Decision:** Implement a simple, readable table strategy:
- Phase 1: render tables as a monospace “table block” (aligned columns, clamped widths) inside a code-block-like container.
- Optional Phase 2: replace table blocks with a horizontal-scroll attachment view for better ergonomics (single view per table, not per cell).
- Table fallback MUST still render LaTeX math segments inside table cell text (e.g. `$\\pi/2$`, `$\\sqrt{2}/2$`) using the same delimiter rules as normal text.

**Why:**
- “Can read it” requirement is satisfied without complex layout machinery.
- Monospace fallback is predictable and low-memory.

### 6) Streaming update policy: cancel + coalesce + only re-render the active assistant message

**Decision:** During streaming, only the latest assistant message is re-rendered. Rendering work is cancellable and updates are coalesced (throttled) to avoid main-thread churn.

**Why:**
- Streaming produces many small deltas; a naive “render on every token” causes CPU spikes and layout thrash.
- Re-rendering only one message keeps work bounded and predictable.

**Implementation shape (high level):**
- A per-message `RenderController` holds the last scheduled task and cancels stale work.
- Throttle window (e.g. 30–60ms) batches updates.
- Cache is width-aware (chat content width affects wrapping).

### 7) Theme mapping and accessibility

**Decision:** Map styles to Hush-defined typography/colors and avoid hardcoded values in the renderer.

**Why:**
- Keeps rendered output consistent with app theme.
- Avoids regressions when design tokens change.

## Risks / Trade-offs

- **[Risk] Many per-message `NSTextView` instances increase memory in very long chats** → **Mitigation:** Provide a future transcript host option; consider collapsing/virtualizing older assistant messages; keep attributed content cached but allow views to be recreated.
- **[Risk] Math attachment rendering can be expensive or cause layout shifts** → **Mitigation:** Strong cache; bounded max render size; fall back to plain LaTeX quickly; optionally render math asynchronously with placeholder source and update in-place.
- **[Risk] Background rendering touches AppKit types unsafely** → **Mitigation:** keep parsing/segmentation off-main, but constrain AppKit object creation (attachments, colors/fonts) to safe contexts; use clear actor boundaries.
- **[Risk] Markdown/table edge cases** → **Mitigation:** prefer readable fallback over strict correctness; add regression fixtures in tests.

## Migration Plan

1. Add new dependencies (Markdown parser + SwiftMath).
2. Add renderer module + unit tests.
3. Update assistant message rendering path to use `NSTextView` host and renderer output.
4. Validate streaming behavior and scroll performance on long transcripts.
5. (Optional) Evaluate table horizontal-scroll attachment and/or transcript host if needed.

Rollback: revert assistant content rendering to plain SwiftUI `Text(message.content)`.

## Open Questions

- Should links be clickable (open in browser) or rendered as styled text-only in the first iteration? (Default: styled text-only.)
- Do we want an explicit “render failed” affordance (icon/tooltip) in addition to showing the raw source?

## Boundary Rules (Required for UX Stability)

These rules are intentionally conservative to avoid turning non-math text into math, and to keep streaming-safe behavior.

- **Math delimiters are ignored inside code**: `$...$` / `$$...$$` MUST NOT be interpreted inside inline code spans or fenced code blocks.
- **Escaping**: `\\$` MUST be treated as a literal dollar sign.
- **Inline math is single-line**: `$...$` MUST NOT span newlines; if a closing `$` is not present, the `$` is rendered literally.
- **Block math is explicit**: `$$...$$` MAY span newlines, but if the closing `$$` is missing (common during streaming), it renders literally until complete.
- **Ambiguity favors literal text**: common currency patterns such as `$10-$20` SHOULD NOT be interpreted as math; when unclear, fall back to literal `$` rendering.
- **Guardrails for pathological content**: the renderer SHOULD cap per-message work (e.g. maximum attachment count, maximum rich-rendered length) and fall back to plain text for the remainder, emitting diagnostics. This protects memory and prevents UI stalls on adversarial or accidental worst-case content.
- **Tables are not a special case**: when using table fallback formatting, math delimiters in cell text SHOULD still be detected and rendered, subject to the same code/currency guardrails.

## Testing Strategy (Core Unit Tests)

Unit tests should be fixture-driven and assert on stable representations (plain text + a lightweight “render summary”) rather than brittle pixel/layout output.

- Markdown conversion smoke tests (no raw markers for common constructs).
- LaTeX segmentation tests:
  - inline vs block detection
  - ignored within code
  - escaped `$`
  - currency patterns (`$10-$20`) remain literal
  - failure fallback preserves source and never crashes
- Table fallback tests:
  - cell content preserved
  - visible row/column separation
  - wide content remains accessible (wrap/clamp strategy)
  - math inside table cells renders (no raw `$...$` markers in output; attachments inserted or graceful fallback)
- Cache behavior tests:
  - width/style are part of the cache key
  - cache is bounded and evicts deterministically
- Streaming coalescing tests using an injectable scheduler/clock:
  - rapid updates coalesce to a bounded rate
  - stale renders are canceled and do not apply out-of-order
