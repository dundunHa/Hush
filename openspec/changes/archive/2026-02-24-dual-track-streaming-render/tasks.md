## 1. Constants & Foundation

- [x] 1.1 Add `streamingFastFlushInterval: Duration = .milliseconds(30)` to RenderConstants
- [x] 1.2 Add `streamingSlowFlushInterval: Duration = .milliseconds(200)` to RenderConstants
- [x] 1.3 Update `throttledUIFlush` to use `streamingSlowFlushInterval` instead of `streamingUIFlushInterval` (keep `streamingUIFlushInterval` as-is for backward compat or remove if no other references)
- [x] 1.4 Verify `streamingCoalesceInterval` remains at 0.05 (50ms) — do NOT modify this value (RenderController coalesce is independent of slow-track throttle)

## 2. Bug Fix: resolveUpdateMode Streaming End

- [x] 2.1 In `MessageTableView.resolveUpdateMode`, replace `isActiveConversationSending` guard with `wasOrIsStreaming` condition: `let wasOrIsStreaming = oldLast.isStreaming || newLast.isStreaming; if wasOrIsStreaming, oldLast.message.id == newLast.message.id, (oldLast.message.content != newLast.message.content || oldLast.isStreaming != newLast.isStreaming) { return .streamingRefresh(row:) }`
- [x] 2.2 Remove `isActiveConversationSending` parameter from `resolveUpdateMode` signature if no longer needed (verify all call sites)
- [x] 2.3 Add unit test: streaming→non-streaming transition with content change triggers `.streamingRefresh`
- [x] 2.4 Add unit test: streaming→non-streaming transition without content change but isStreaming flip triggers `.streamingRefresh`
- [x] 2.5 Add unit test: non-streaming rows (both old/new isStreaming=false) with identical content still return `.noOp`
- [x] 2.6 Add unit test: non-streaming content change (both isStreaming=false, content differs) returns `.noOp` or appropriate mode (not `.streamingRefresh`)

## 3. Cell Anti-Regression (D6)

- [x] 3.1 Add `private var streamingDisplayedLength: Int = 0` to `MessageTableCellView`
- [x] 3.2 In `updateStreamingText`, after setting bodyLabel, record `streamingDisplayedLength = content.count`
- [x] 3.3 In `configure`, before Phase 1 plain text write for assistant messages: if `currentRow?.isStreaming == true && row.isStreaming == true && row.message.content.count < streamingDisplayedLength`, skip the plain text bodyLabel assignment but still proceed to trigger RenderController
- [x] 3.4 In `configure`, when `row.isStreaming == false`, unconditionally write plain text and reset `streamingDisplayedLength = 0`
- [x] 3.5 In `prepareForReuse`, reset `streamingDisplayedLength = 0`

## 4. Fast-Track Cell Update Path

- [x] 4.1 Add `func updateStreamingText(_ content: String)` to `MessageTableCellView` — sets bodyLabel.attributedStringValue to plain NSAttributedString with standard font/color attributes, no RenderController interaction; records `streamingDisplayedLength`
- [x] 4.2 Add `private var lastStreamingHeight: CGFloat = 0` to `MessageTableView` for height-change detection
- [x] 4.3 Add `func updateStreamingCell(messageID: UUID, content: String)` to `MessageTableView` — locates row by scanning `rows` array for matching messageID, gets visible cell via `tableView.view(atColumn:0, row:, makeIfNecessary:false)`, calls `cell.updateStreamingText`, compares `bodyLabel.intrinsicContentSize.height` with `lastStreamingHeight` and only calls `tableView.noteHeightOfRows(withIndexesChanged:)` if height changed, calls `scrollToBottom()` if `!userHasScrolledUp`
- [x] 4.4 Add `func pushStreamingContent(messageID: UUID, content: String)` to `ConversationViewController` — forwards to `messageTableView.updateStreamingCell(messageID:content:)`
- [x] 4.5 Add `func pushStreamingContent(conversationId: String, messageID: UUID, content: String)` to `AppContainer` — guards `conversationId == activeConversationId`, gets scene via `hotScenePool?.sceneFor(conversationID:)`, calls `scene.pushStreamingContent(messageID:content:)`
- [x] 4.6 Verify `HotScenePool.sceneFor(conversationID:)` returns active scene correctly for the fast-track path (already public, confirm no additional changes needed)

## 5. Dual-Track Flush in RequestCoordinator

- [x] 5.1 Add `var pendingFastFlush: Task<Void, Never>?` and `var lastFastFlush: ContinuousClock.Instant?` to `SessionFlushState`
- [x] 5.2 Implement `throttledFastFlush(requestID:conversationId:messageID:content:)` — throttles at `streamingFastFlushInterval`, calls `container.pushStreamingContent(conversationId:messageID:content:)` on flush
- [x] 5.3 Modify `throttledUIFlush` to use `streamingSlowFlushInterval` instead of the old interval
- [x] 5.4 Update `handleDelta` to call both `throttledFastFlush` and `throttledUIFlush` (now slow-track) for active conversation deltas
- [x] 5.5 Ensure first delta path (creating new assistant message via `appendMessage`) does NOT apply slow-track throttle — record `lastUIFlush = now` immediately after insert to prevent double-flush
- [x] 5.6 Update `flushPendingUIUpdate` to also flush any pending fast-track content (cancel task + immediate push)
- [x] 5.7 Ensure `cleanupFlushState` cancels both fast and slow pending tasks

## 6. Conversation Switch Sync

- [x] 6.1 In `AppContainer` (or RequestCoordinator), when active conversation changes to a conversation with a running stream, immediately call `pushStreamingContent` with the current `accumulatedText` from the active request state
- [x] 6.2 Add test: switching to a streaming conversation results in immediate content push

## 7. Cleanup & Safety

- [x] 7.1 Ensure `cleanupFlushState` in RequestCoordinator cancels `pendingFastFlush` in addition to `pendingUIFlush` and `pendingStreamingFlush`
- [x] 7.2 In `updateStreamingCell`, validate messageID still exists in `rows` before accessing cell (guard against stale Task firing after row removal)
- [x] 7.3 Verify conversation deletion path cancels any running request's throttle Tasks (trace from `deleteConversation` → `cancelRequest` → `cleanupFlushState`)
- [x] 7.4 Add `cancelThrottleTasksForConversation(_:)` to RequestCoordinator and call from `evictScene` to cancel pending throttle Tasks on scene eviction

## 8. Integration & Edge Cases

- [x] 8.1 Verify fast-track gracefully handles nil scene (cell not visible / no active scene): `pushStreamingContent` should silently return if `hotScenePool?.sceneFor` returns nil or cell is not visible
- [x] 8.2 Verify `updateStreamingCell` correctly identifies the streaming row by messageID (not last-row assumption)
- [x] 8.3 Verify fast-track works correctly with empty messages (new conversation before first delta — no streaming row yet, should no-op)
- [x] 8.4 Verify back-to-back fast flushes with identical content are coalesced (no redundant label assignments)
- [x] 8.5 Verify conversation switch back to streaming conversation shows latest content immediately

## 9. Testing

- [x] 9.1 Unit test: `MessageTableCellView.updateStreamingText` sets bodyLabel correctly and updates `streamingDisplayedLength`
- [x] 9.2 Unit test: Anti-regression — call `updateStreamingText` with longer content, then `configure` with shorter streaming content → bodyLabel NOT overwritten
- [x] 9.3 Unit test: Anti-regression — `configure` with `isStreaming=false` always overwrites regardless of `streamingDisplayedLength`
- [x] 9.4 Unit test: `AppContainer.pushStreamingContent` routes to active scene only (non-active returns silently)
- [x] 9.5 Unit test: `throttledFastFlush` throttles at correct interval and flushes latest content
- [x] 9.6 Unit test: `flushPendingUIUpdate` flushes both fast and slow tracks
- [x] 9.7 Integration test: fast-track displays longer content → slow-track configure with shorter content → verify no visual regression → slow-track rich render completes → verify final state correct
- [x] 9.8 Build + run `make test` to verify no regressions
- [x] 9.9 Run `make fmt` to ensure code style compliance
- [x] 9.10 Unit test: `cancelThrottleTasksForConversation` clears pending throttle Tasks for evicted conversation
- [x] 9.11 Unit test: fast-track height invalidation triggers `noteHeightOfRows` when height changes, skips when stable
- [x] 9.12 Unit test: fast-track `scrollToBottom` called only when `userHasScrolledUp` is false
