## Context

Hush 的流式聊天渲染链路当前为单路径：SSE delta → RequestCoordinator.throttledUIFlush(100ms) → AppContainer.updateMessage (@Published) → SwiftUI diff → HotScenePoolController.forwardUpdateToActiveScene (diff guard) → MessageTableView.apply → resolveUpdateMode → reloadData(forRowIndexes:) → cell.configure → RenderController.requestStreamingRender(50ms coalesce) → Markdown render → Combine sink → bodyLabel。

这条链路存在两类问题：
1. **断流 bug**：SwiftUI diff 可能不传导 updateNSViewController；HotScenePoolController 的 diff guard (messageCount/lastContentHash/isSending/generation) 可能误判为"无变化"而 return；resolveUpdateMode 在 `isActiveConversationSending == false` 时跳过 streamingRefresh 走 `.noOp` 导致流式结束最后一跳丢失。
2. **延迟问题**：5 个瓶颈叠加（100ms throttle + SwiftUI cycle + diff guard + reloadData + 50ms coalesce + render），端到端 150-300ms+，无法实现逐字丝滑体验。

关键约束：
- NSTableView 使用 `usesAutomaticRowHeights = true`，行高由 Auto Layout 自动计算
- TailFollow 状态机独立于 reloadData，`performScrollToBottom` 只调 `scrollRowToVisible`
- `tableView.view(atColumn:row:makeIfNecessary:false)` 可直接获取可见 cell 而不触发复用
- `noteHeightOfRows(withIndexesChanged:)` 可在不 reload 的情况下通知行高变化
- RenderController 共享底层 renderer + scheduler，创建成本低但不必要

## Goals / Non-Goals

**Goals:**
- 流式期间纯文本以 ~30ms 粒度逐 chunk 显示，用户感知为"逐字吐字"
- 富文本 markdown 渲染以 ~200ms 粒度异步追赶，最终替换纯文本
- 消除断流 bug：快轨绕过 SwiftUI diff 和 HotScenePoolController diff guard 两个断点
- 修复 resolveUpdateMode 流式结束最后一跳 `.noOp` bug
- 保持 `@Published messages` 模型最终一致性（慢轨负责）
- 保持 TailFollow 滚动行为正确
- 首个 delta 立即显示消息气泡（不节流）
- 防止 slow-track 用旧内容覆盖 fast-track 已显示的新内容（防回退）

**Non-Goals:**
- 不做增量 markdown 渲染（复杂度高，收益不确定）
- 不改 RenderController 生命周期/缓存策略/coalesce 间隔（当前 50ms 设计在两轨模式下可正常工作）
- 不改 HotScenePool 的 scene 管理逻辑
- 不改后台会话的流式处理（仍走 markNeedsReload 现有路径）

## Decisions

### D1: 双路径 flush 而非改造单路径

**选择**：在 RequestCoordinator.handleDelta 中拆分为两个独立 throttle 路径。

**备选方案**：
- A: 调低现有 throttle 间隔到 30ms → 仍经过 SwiftUI/reloadData，无法解决断流
- B: 用 Combine/NotificationCenter 从 RequestCoordinator 直接通知 cell → 跳层太多，耦合差
- C: 双路径 flush（推荐）→ 快轨高频直达 AppKit，慢轨低频维护模型一致性

**理由**：方案 C 最小侵入——快轨是纯 UI 层面的新增路径，慢轨复用现有全部逻辑只是降低频率。两轨解耦意味着任何一轨出问题不影响另一轨。

### D2: 快轨通过 AppContainer → HotScenePool → ConversationVC → MessageTableView 链路

**选择**：在 AppContainer 上新增 `pushStreamingContent` 方法，通过已有的 `hotScenePool.sceneFor(conversationID:)` 拿到活跃 scene，转发到 ConversationVC 新增的方法，最终到达 MessageTableView。

**备选方案**：
- A: 让 RequestCoordinator 直接持有 MessageTableView 引用 → 严重违反层级
- B: 用 NotificationCenter post → 松耦合但有广播开销和类型不安全
- C: 沿现有对象图传递（推荐）→ 每层加一个方法，类型安全，`@MainActor` 天然保证

**理由**：方案 C 沿现有对象引用链传递，不引入新的耦合方式。HotScenePool 已有 `sceneFor(conversationID:)` 和 `activeConversationID`，无需修改。

### D3: 快轨只更新纯文本，不触发 RenderController

**选择**：`updateStreamingText` 只设置 `bodyLabel.attributedStringValue` 为 plain NSAttributedString，不调 `requestRender`。

**理由**：快轨追求极致轻量（一次 NSAttributedString 赋值）。富文本由慢轨的 `cell.configure → RenderController` 路径负责。当慢轨的 configure 执行时，会用 fingerprint 检测到内容变化，创建/复用 RenderController 进行完整渲染，渲染完成后通过 Combine sink 替换 bodyLabel 内容。

### D4: 使用 noteHeightOfRows 代替 reloadData 刷新行高（带高度变化检测）

**选择**：快轨更新后检测 bodyLabel 高度变化，仅在高度确实改变时调 `tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))`。

**理由**：`usesAutomaticRowHeights = true` 下，`noteHeightOfRows` 触发 Auto Layout 重算指定行高度，不会触发 `tableView(_:viewFor:row:)` 和 cell 复用。比 `reloadData(forRowIndexes:)` 轻量得多。但每 30ms 无脑触发会造成主线程抖动，因此需检测高度变化：比较 bodyLabel.intrinsicContentSize.height 与上次记录值，仅变化时才调用。

### D5: 修复 resolveUpdateMode 流式结束条件（精确门禁）

**选择**：将 `isActiveConversationSending` 门禁替换为 `wasOrIsStreaming`（old/new 任一 isStreaming 为 true），精确覆盖流式生命周期内的所有变更。

**代码形式**：
```swift
let wasOrIsStreaming = oldLast.isStreaming || newLast.isStreaming
if wasOrIsStreaming,
   oldLast.message.id == newLast.message.id,
   (oldLast.message.content != newLast.message.content
    || oldLast.isStreaming != newLast.isStreaming) {
    return .streamingRefresh(row: newCount - 1)
}
```

**理由**：`isActiveConversationSending` 在流结束时变为 false，导致最后一跳被吞。而 `wasOrIsStreaming` 确保：
- 流式过程中（old/new 都 isStreaming）→ 命中
- 流结束（old isStreaming=true, new isStreaming=false）→ 命中
- 非流式场景（old/new 都 isStreaming=false）→ 不命中，走 `.noOp` 或其他分支

避免了"无条件移除 guard 导致非流式编辑误触发"的过宽问题。

### D6: Cell 层防回退（Anti-Regression）

**选择**：在 `MessageTableCellView` 维护 `streamingDisplayedLength: Int`，作为防回退判断依据。

**规则**：
1. `updateStreamingText` 每次更新后记录 `streamingDisplayedLength = content.count`
2. `configure` 中的 Phase 1 plain text 写入前：若 cell 正在流式（`currentRow?.isStreaming == true`）且 incoming 的 `isStreaming == true` 且 `incoming.content.count < streamingDisplayedLength` → 跳过 plain text 写入，但仍触发 RenderController 排队
3. 当 incoming 的 `isStreaming == false`（最终态）→ 无条件允许写入，重置 `streamingDisplayedLength = 0`
4. `prepareForReuse` 时重置 `streamingDisplayedLength = 0`

**理由**：最小侵入——不需要 fast-track 去污染 model，不需要重塑渲染管线。防回退放在消费端（cell 内），规则简单且单调。

### D7: 慢轨节流在 RequestCoordinator 层，不改 RenderController coalesce

**选择**：慢轨的 200ms 节流只作用于 `RequestCoordinator.throttledUIFlush`（输入侧），RenderController 的 `streamingCoalesceInterval` 保持 50ms 不变。

**备选方案**：
- A: 全局改 RenderController coalesce 到 200ms → 误伤非流式渲染（窗口 resize、主题切换等）
- B: 只在 RequestCoordinator 层节流输入频率（推荐）→ 精准控制慢轨更新频率，不影响其他渲染路径

**理由**：`streamingCoalesceInterval` 被 RenderController 全局使用。将其改为 200ms 会让所有渲染场景响应变慢。在 RequestCoordinator 层控制 updateMessage 的调用频率，是最精准的节流点。

### D8: 首个 delta 不节流立即插入

**选择**：handleDelta 中首次创建 assistant ChatMessage 时，直接调用 `appendMessage` 并立即执行一次 slow-track flush（不走节流），确保消息气泡即时出现。从 delta#2 起，fast-track 接管低延迟纯文本推送。

**理由**：如果首个 delta 也走 200ms 慢轨节流，用户会有明显的等待感（点击发送后 200ms 无反应）。首 delta 立即插入保证了首屏响应的体感。

### D9: 对话切换回流式会话时立即同步

**选择**：当用户切换到一个正在流式的会话时，在 switch 事件中立即调用一次 `pushStreamingContent` 用当前累积内容刷新 UI。

**理由**：用户从会话 A 切到 B 再切回 A 时，如果 slow-track 正好没到刷新点，UI 会短暂显示旧内容。一次立即同步消除这个可见延迟。

## Risks / Trade-offs

**[Risk] 快轨/慢轨内容不一致窗口** → 快轨显示的纯文本可能比 `messages[index].content` 多 ~200ms 的内容。Mitigation：D6 cell 层防回退机制确保 slow-track configure 不会用旧 plain text 覆盖新内容。当 slow-track 的 rich render 完成后，Combine sink 写入的 attributedString 会自然替换 fast-track 的 plain text（此时内容已追上）。

**[Risk] noteHeightOfRows 抖动** → 频繁触发 Auto Layout 重算可能造成滚动抖动。Mitigation：D4 规定仅在 bodyLabel.intrinsicContentSize.height 确实变化时才调用。同时 scrollToBottom 仅在 isFollowingTail 时执行。

**[Risk] cell 不在视口中时快轨退化** → `tableView.view(…makeIfNecessary: false)` 返回 nil。Mitigation：这是正确行为——不可见 cell 不需要实时更新。慢轨会更新 model，下次 cell 变可见时 configure 会获取最新内容。

**[Risk] 多会话并发时快轨只更新 active** → 后台会话的流式不走快轨。Mitigation：后台会话本来就不需要实时 UI，慢轨 + markNeedsReload 足够。

**[Risk] 节流 Task 在 cell 回收/会话删除后触发** → 延迟 Task 可能操作已释放/回收的 cell。Mitigation：更新时以 messageID 查当前 rows 确认仍存在；Task 句柄在流结束/对话删除/场景回收时显式 cancel。

**[Risk] content.hashValue 碰撞** → RenderInputFingerprint 使用 `content.hashValue` 可能碰撞导致跳过更新。Mitigation：这是既有风险，不在此次变更范围内。如确需修复，可在 fingerprint 中混入 `content.count` 作为辅助校验（独立优化）。

**[Risk] 滚动锚点一致性** → fast-track 改 view + 触发高度变化时，如果同时有行插入（系统消息等），可能破坏尾随底部的锚定。Mitigation：所有滚动决策统一使用 TailFollowStateMachine 的 `isFollowingTail` 判定，不引入新的滚动入口。
