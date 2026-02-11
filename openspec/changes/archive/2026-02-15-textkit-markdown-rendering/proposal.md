## Why

Hush currently renders assistant output as plain text, which prevents users from comfortably reading common LLM-formatted content such as Markdown lists, code blocks, tables, and LaTeX math. As assistant responses get longer (and often stream), a naive SwiftUI view-tree Markdown renderer risks jank and higher memory due to excessive view count and repeated layout work. We need a macOS-native rendering approach that keeps scrolling smooth, memory stable, and failures non-fatal.

## What Changes

- Render **assistant** messages using a high-performance Markdown pipeline that targets macOS TextKit (`NSTextView` / TextKit 2) as the primary layout and drawing engine.
- Keep **user** messages as bubble UI initially; assistant output is rendered directly (no bubble) to prioritize readability and density.
- Support common Markdown constructs needed for LLM output:
  - Headings, emphasis, paragraphs, links, inline code, fenced code blocks, lists, blockquotes
  - Tables with a “readable” strategy (horizontal scroll attachment or monospace fallback), not strict GitHub parity
- Add LaTeX math rendering for `$...$` and `$$...$$` using native attachments (e.g. SwiftMath), optimized for:
  - **100% success** on common formulas
  - **~80% success** on complex macros
  - **0 crashes** with a graceful fallback when unsupported (show original LaTeX + copy affordance)
- Define conservative math delimiter handling so non-math uses of `$` remain readable (e.g. code blocks and currency like `$10-$20`).
- Make rendering **modular and swappable**: a single cohesive renderer module with a stable API so we can later change hosting strategy (per-message vs transcript) without rewriting the chat UI.
- Add caching + throttled incremental updates so streaming content remains smooth and does not spike CPU or memory.
- Scope note: for now, Hush continues to support copying **a single message at a time**; cross-message selection/copy remains out of scope.
- Out of scope: full GitHub Markdown parity, MathJax-level macro coverage, and any WebView/HTML rendering stack.

## Capabilities

### New Capabilities
- `markdown-message-rendering`: Render assistant message content as Markdown with LaTeX attachments and table fallbacks, optimized for smooth scrolling, low memory, and graceful degradation.

### Modified Capabilities
- (none)

## Impact

- Affected code:
  - `Hush/Views/Chat/MessageBubble.swift` (assistant rendering path)
  - `Hush/Views/Chat/ChatScrollStage.swift` (layout + scroll behavior remains, but assistant rows change)
  - New cohesive renderer module (e.g. `Hush/HushRendering/*` or similar)
- Dependencies:
  - Introduce a Markdown parser suitable for GFM-like output (AST-based)
  - Introduce a native LaTeX renderer for attachments (no WebView / no MathJax goal)
- Testing:
  - New unit tests for parsing → attributed output, LaTeX detection and fallback behavior, table fallback formatting, caching keys, and streaming update throttling.
