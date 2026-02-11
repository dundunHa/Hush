# Learnings

- Used ChatWindowing pure function to compute a stabilized window of messages for ChatScrollStage.
- Removed per-message GeometryReader frame tracking which caused massive `visible.recompute` spikes during scrolling.
- Tracked top-visible message via simple `onAppear` and `onDisappear` on message bubbles, updating the window state lazily and ensuring the window range never falls completely out of view.
- Perf tests confirmed `visible.recompute.count` is reduced from thousands down to strictly the calls explicitly made when window shifting.

## Task 5: Older-load trigger & auto-scroll & streaming protection
- The current older-load trigger is `onAppear` of a 1pt clear view in `topPaginationSection`. Due to windowing or swiftui layout jitters, this can repeatedly fire or fire incorrectly. We need a stable trigger.
- The `userHasScrolledUp` variable handles the streaming protection perfectly. If it`s true, `resolveCountChangeAutoScrollAction` returns `.none`.
- We need to add `PerfTrace.count(PerfTrace.Event.scrollAdjustToBottom, fields: ["during_streaming": "true/false", "suppressed": "true/false"])`
- To track near-top, we can add a `TopAnchorPreferenceKey` on a view at the very top (just like `BottomAnchorPreferenceKey` on `scrollAnchorID`), and measure its distance from `0` to determine if we should load older messages, debounced/throttled by `olderLoadThrottleInterval`.

## Task 7: Conversation switch fast-first optimization
- Cache-hit conversation switch now sets status to `Ready` immediately after snapshot apply, instead of staying in a temporary refreshing state.
- Added switch-phase PerfTrace durations: `switch.snapshotApplied`, `switch.layoutReady`, `switch.richReady`, plus two phase-gap metrics: `switch.snapshot_to_layoutReady` and `switch.snapshot_to_richReady`.
- `ChatScrollStage.resetForConversationSwitch` now avoids redundant animated switch scrolling: if message list is empty it skips immediate `scrollTo`; switch/switch-load auto-scroll uses non-animated bottom alignment.
- Added task-cancel guard in deferred `requestScrollToBottom` to avoid stale queued scroll work after rapid consecutive conversation switches.
- For non-streaming rich render scheduling, fallback unknown-rank (`Int.max`) requests remain `.deferred`, while non-visible/off-tail history now falls to `.idle` earlier to preserve budget for window/tail work.
- Full test run remains green after updating startup prewarm behavior expectation (`Ready` instead of `Refreshing thread...`).
- Attempted to collect runtime PerfTrace samples via `log show` into `.sisyphus/evidence/task-7-perf-log.json`, but current capture window contains no PerfTrace events (`[]`), so p95 deltas cannot be computed from this run alone.

## Task 6: TextKit peak convergence — ensureLayout & reconcile cost reduction
- **Root cause of redundant ensureLayout**: `updateNSView` had `|| !context.coordinator.tableAttachmentHost.isEmpty` in `shouldEnsureLayout` condition, forcing layout on every SwiftUI update cycle for any message with table attachments — even when content/width hadn't changed.
- **Fix**: Removed the `!isEmpty` condition. Table reconcile is already gated by its own fingerprint (`lastReconcileFingerprint`), so re-layout is unnecessary just because tables exist.
- **sizeThatFits already had caching**: `cachedHeightIfValid` with 0.5pt width threshold was already in place. No additional width threshold needed — the existing cache handles repeated calls with same identity+width.
- **PerfTrace instrumentation**: Added `PerfTrace.measure(Event.textEnsureLayout)` around both `ensureLayout` call sites (updateNSView, sizeThatFits) with `caller` field to distinguish. Added `PerfTrace.measure(Event.attachmentsReconcile)` around reconcile.
- **TableAttachmentHost descriptor fingerprint**: Added `DescriptorFingerprint` (keys + frame hashes) to `reconcileImpl`. When fingerprint matches last reconcile, skips all view manipulation (remove stale, create new, reposition). `scanDescriptors` still runs (lightweight attribute enumeration), but the expensive subview add/remove/reposition is skipped.
- **Existing tests all pass**: 5 tests in `TableAttachmentHostReuseTests` — reuse, preserve offset, stale removal, content change, duplicate ordinals.

## Task 10: AppKit fallback route
- Evaluation-first result: `.sisyphus/evidence/perf-baseline-summary.json` has `totalEntries = 0` and no `switch.snapshot_to_layoutReady` samples, so current baseline cannot prove `p95 <= 100ms`.
- Decision: implemented opt-in AppKit fallback route behind `HUSH_APPKIT_CONVERSATION` instead of replacing SwiftUI path.
- Added `ConversationViewControllerRepresentable` + `ConversationViewController` and `MessageTableView` (`NSTableView` reuse path) for conversation rendering.
- AppKit route reuses existing `MessageRenderRuntime` + `RenderController` for assistant rich text and calls `reportActiveConversationRichRenderReadyIfNeeded()` for switch-rich tracing.
- AppKit route keeps switch tracing parity by calling `markConversationSwitchLayoutReady()` after conversation generation changes and emitting `scroll.adjustToBottom` trace fields on bottom scroll actions.

## Task 9: Accessibility compatibility for windowed list
- Add `.accessibilityElement(children: renderHint.isVisible ? .contain : .ignore)` and `.accessibilityHidden(false)` to MessageBubble so that off-window items are still presented to VoiceOver, but with a reduced label indicating its index (`message X of Y`).
- Full-text selection on windowed items is inherently supported by `AttributedTextView` (which uses `NSTextView`). Selection inside the view works perfectly, and dragging selection off window does not cause layout spikes because windowing prevents `visible.recompute` loop.

## Task 8: Tests-after regression coverage
- Extended `ChatScrollStageAutoScrollPolicyTests` from 3 → 20 tests covering: scroll suppression when `userHasScrolledUp` is true (assistant append, streaming, multiple sequential appends), user message overriding scroll-up state, older-load prepend handling (no auto-scroll in both scrolled-up and pinned states), count decrease/no-change edge cases, switch-load priority over all other conditions, rapid A→B→C switch simulation, stale conversation message rejection, system/nil role edge cases, and PerfTrace event name validation.
- Created `ConversationWindowingTests` with 11 tests covering: streaming auto-scroll with windowing (always includes last message, shifts to tail, works when pinned), streaming with growing message count, rapid consecutive switch producing independent windows without stale range bleed, switch from large to small conversation resetting window, fresh computation without previousWindowRange, anchor at buffer boundary triggering window shift, empty conversation producing empty range, older-load prepend shifting window by delta, and multiple older-load cycles maintaining consistency.
- Key discovery: `resolveCountChangeAutoScrollAction` is a pure static function — ideal for deterministic unit testing without UI dependencies. Similarly, `ChatWindowing.computeWindow` is a pure function taking `ChatWindowingInput` and returning `ChatWindowingOutput`.
- `userHasScrolledUp` gates ALL auto-scroll behavior except user-sent messages (which always force scroll-to-bottom). `pendingSwitchScrollWhenMessagesAppear` takes priority over all other conditions. `didPrependOlderMessages` always returns `.none`.
- `RuntimeConstants.conversationMessagePageSize` is 9, used as tailCount in windowing tests.
- LSP reports `Cannot find 'PerfTrace' in scope` for test files — this is a SourceKit indexing issue; actual xcodebuild compiles and runs fine.
- All 31 new tests pass. Evidence saved to `.sisyphus/evidence/task-8-regression-tests.txt`.
