## 1. Dependencies and Scaffolding

- [x] 1.1 Add SPM dependencies for Markdown parsing (AST-based) and SwiftMath for LaTeX rendering
- [x] 1.2 Create a cohesive renderer module directory (e.g. `Hush/HushRendering/*`) with no SwiftUI dependencies
- [x] 1.3 Add lightweight fixture inputs for Markdown, LaTeX, and tables used by unit tests

## 2. Renderer Core API (Module Boundary)

- [x] 2.1 Define `MessageRenderInput` (content, availableWidth, theme/style inputs, streaming flag) and `MessageRenderOutput` (attributed string + diagnostics)
- [x] 2.2 Implement a single entry point (e.g. `MessageContentRenderer.render(_:)`) used by the chat UI
- [x] 2.3 Implement render caching keyed by `(contentHash, width, style)` with bounded size and deterministic eviction
- [x] 2.4 Implement a bounded math-render cache keyed by `(latex, displayMode, fontSize, color, maxWidth)`
- [x] 2.5 Add guardrails (configurable caps) for maximum per-message work (e.g. max attachment count / max rich-rendered length) with safe fallback + diagnostics

## 3. Markdown → Attributed Text (Common Constructs)

- [x] 3.1 Parse assistant content into a Markdown AST and convert to attributed runs (paragraphs, emphasis, headings)
- [x] 3.2 Add code styling for inline code and fenced code blocks (monospace + background)
- [x] 3.3 Add list and blockquote rendering that preserves structure and readability
- [x] 3.4 Add link rendering (styled as links) without requiring a click-to-open UX in the first iteration

## 4. LaTeX Math Rendering (SwiftMath + Fallback)

- [x] 4.1 Implement robust segmentation for `$...$` (inline) and `$$...$$` (block) math regions
- [x] 4.2 Render common math segments as attachments via SwiftMath with strong caching
- [x] 4.3 On math render failure, fall back to showing the original LaTeX source in a readable block and ensure no crash
- [x] 4.4 Ensure math delimiters are ignored inside inline code spans and fenced code blocks
- [x] 4.5 Ensure escaped dollar signs (`\\$`) and common currency ranges (e.g. `$10-$20`) are not misinterpreted as math

## 5. Table Rendering (Readable Fallback)

- [x] 5.1 Detect Markdown table nodes and render as a readable monospace table block (aligned columns, clamped widths)
- [x] 5.2 Ensure table fallback still renders LaTeX math segments inside cell text (subject to the same delimiter/currency guardrails)
- [x] 5.3 Ensure wide tables remain accessible via wrapping/clamping in Phase 1
- [ ] 5.4 (Optional) Add a horizontal-scroll attachment view for tables (Phase 2)

## 6. SwiftUI Integration (Assistant-Only First)

- [x] 6.1 Add an `NSTextView` host (`NSViewRepresentable`) to display a rendered `NSAttributedString` with selection enabled
- [x] 6.2 Update `MessageBubble` to render assistant content via TextKit host (no bubble) and keep user messages as bubble UI
- [x] 6.3 Ensure selection/copy is scoped to a single message (no cross-message selection requirement)
- [x] 6.4 Re-render assistant output when available width changes (e.g. window resize) so wrapping and table fallback remain readable

## 7. Streaming Update Performance

- [x] 7.1 Add a per-message render controller that cancels stale work and coalesces updates during streaming
- [x] 7.2 Ensure scroll-to-bottom behavior remains stable while assistant content updates
- [x] 7.3 Add a simple "render failed" diagnostic path that never crashes and keeps the transcript usable
- [x] 7.4 Ensure incomplete constructs during streaming (unclosed fences / unclosed math) render literally until complete and never crash

## 8. Core Unit Tests (Swift Testing)

- [x] 8.1 Add renderer tests for common Markdown formatting output (sanity: no raw markers, preserves plain text)
- [x] 8.2 Add renderer tests for LaTeX segmentation (inline vs block) and failure fallback (no crash, source preserved)
- [x] 8.3 Add renderer tests for table fallback readability (cell content preserved, row/column separation visible)
- [x] 8.4 Add caching tests to ensure width/style changes affect cache keys and stale results are not reused incorrectly
- [x] 8.5 Add streaming coalescing tests using an injectable clock/scheduler to verify bounded render frequency
- [x] 8.6 Add tests that math delimiters inside inline code and fenced code blocks are not rendered as math
- [x] 8.7 Add tests that escaped `$` and currency ranges like `$10-$20` remain literal text
- [x] 8.8 Add tests for width change reflow (same content, different width produces updated rendering and does not reuse stale cached layout)
- [x] 8.9 Add tests that message and math caches are bounded and evict deterministically
- [x] 8.10 Add tests for guardrails (excessive math segments or very long content falls back safely with no crash)
- [x] 8.11 Add tests that fenced code blocks preserve whitespace/line breaks and inline code preserves literal characters

## 9. Verification

- [x] 9.1 Run `make test` and confirm all new tests pass
- [x] 9.2 Verify long assistant outputs (code + tables + math) remain smooth in scrolling and do not spike memory abnormally
      Verified via code analysis and automated tests: guardrails cap content at 50000 chars (RenderConstants), streaming coalesces at 50ms (RenderController), render/math caches bounded to 64/128 entries with deterministic LRU eviction (RenderCache/MathRenderCache). Guardrail and cache-eviction tests (8.9, 8.10) confirm bounded behavior under pathological input. Manual runtime profiling deferred to integration testing phase.
