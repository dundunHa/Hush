## 1. Single-Path Routing Cleanup

- [x] 1.1 Refactor `Hush/Views/Chat/ChatDetailPane.swift` to remove runtime chat-route branching and always host `HotScenePoolRepresentable` + `ComposerDock`.
- [x] 1.2 Remove the single-VC fallback bridge (`ConversationViewControllerRepresentable`) from `Hush/Views/Chat/AppKit/ConversationViewController.swift` and update call sites.
- [x] 1.3 Remove obsolete route gate plumbing tied to `HUSH_APPKIT_CONVERSATION` / `HUSH_HOT_SCENE_POOL` from chat routing code.
- [x] 1.4 Delete legacy SwiftUI chat-route files (`ChatScrollStage.swift`, `MessageBubble.swift`, `ScrollTelemetryBridge.swift`) and resolve compile references.
- [x] 1.5 Delete `Hush/Views/Chat/AppKit/HotScenePoolFeature.swift` and update any remaining references/tests.

## 2. Script & Docs Alignment

- [x] 2.1 Update `Makefile` run output/env handling so it no longer advertises runtime chat-route switching.
- [x] 2.2 Update `doc/chat-rendering/` documents to describe AppKit single-path behavior and remove stale dual-route guidance.
- [x] 2.3 Update any AGENTS or architecture map entries that still describe SwiftUI chat rendering as an active route.

## 3. MessageTableView Incremental Update Strategy

- [x] 3.1 Refactor `MessageTableView.apply()` to compute update mode safely (generation switch/full reload vs append insert vs same-row streaming refresh).
- [x] 3.2 Add explicit prepend/history-load detection branch that falls back to full reload to avoid row index corruption.
- [x] 3.3 Preserve tail-follow semantics across all update modes (switch, streaming, append, prepend).
- [x] 3.4 Ensure metrics/report hooks in `apply()` still fire with equivalent semantics after incrementalization.
- [x] 3.5 Add/extend tests covering append, prepend, same-count streaming update, and generation switch behavior.

## 4. MessageTableCellView Configure Dedup

- [x] 4.1 Add render-input fingerprint state to `MessageTableCellView` covering message identity, content fingerprint, generation, streaming state, and width/style key.
- [x] 4.2 Short-circuit `configure()` when fingerprint is unchanged without breaking existing visible output.
- [x] 4.3 Ensure fingerprint invalidation works on reuse/cancel paths so stale output is not pinned incorrectly.
- [x] 4.4 Add tests for dedup-hit skip and dedup-miss re-render behavior.

## 5. Near-Viewport Prewarm

- [x] 5.1 Implement lookahead prewarm trigger in AppKit table scroll telemetry path (without relying on unavailable NSTableView prefetch APIs).
- [x] 5.2 Add runtime calls that schedule low-priority prewarm only for eligible non-streaming assistant rows missing cache.
- [x] 5.3 Ensure prewarm scheduling is cancellable/bounded and does not interfere with visible-row rendering latency.
- [x] 5.4 Add tests for prewarm eligibility and cache-hit skip behavior.

## 6. Rendering Responsiveness Safeguards

- [x] 6.1 Audit and reduce redundant render requests in streaming path while preserving current actor/thread-safety boundaries.
- [x] 6.2 Keep Markdown/LaTeX/table rendering behavior unchanged under optimized update flow (output parity guard).
- [x] 6.3 Add regression tests for streaming responsiveness and stale-update prevention after optimization changes.

## 7. Test Suite & Cleanup

- [x] 7.1 Remove or rewrite tests that only validate deleted dual-route/feature-flag behavior.
- [x] 7.2 Add/adjust tests for single-path route invariants and hot-scene-pool-only behavior.
- [x] 7.3 Run targeted suites for routing, table view, cell rendering, scheduler, and pool lifecycle.
- [x] 7.4 Run full `make test` and fix any regressions introduced by route consolidation/perf changes.
