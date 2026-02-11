# Draft: Composer 聚焦导致底部消息“吃掉一行”

## 现象（用户描述 / 目标问题）
- 当聊天列表已经滚动到最底部时，点击底部 `ComposerDock` 的输入框（`TextEditor`）获得焦点后，**最后一条消息的最后一行会被截断/看起来被 dock 遮住**。
- 随后点击聊天列表区域，最后一行又会显示出来（通常伴随极小幅度的滚动或重布局）。

## 复现步骤（用户提供）
1. 打开一段较长的最后一条消息，滚动到底部，确保尾部刚好贴底。
2. 点击底部输入框让其获得焦点（必要时让输入框高度发生变化）。
3. 观察最后一条消息底部被截断；再点击聊天区域，截断消失。

## 期望
- 无论输入框聚焦或 dock 高度变化，最后一条消息都应完整可见，不应被“吃掉一行”。

## 代码证据（已在仓库中确认）

### 1) shrink 时同步 scrollToBottom（高度变化时序敏感）
- `Hush/Views/Chat/AppKit/MessageTableView.swift:166-184`（`override func layout()`）
  - 当 view 高度变小（例如 composer dock 变高）且满足 `!userHasScrolledUp` 且 `!rows.isEmpty` 时，**同步调用** `scrollToBottom()`。
  - `scrollToBottom()` 只是 `tableView.scrollRowToVisible(rows.count - 1)`。

补充：同一文件里还存在更“正式”的滚动路径：
- `MessageTableView.performScrollToBottom(animated:reason:)` 会先发送 `TailFollow.reduce(event: .programmaticScrollInitiated)`，再滚动。
- 但 `layout()` 当前走的是 **直接** `scrollToBottom()`，不会触发 `programmaticScrollGrace` 保护窗。

### 2) pinned / tail-follow 的判定依赖 clipView visibleMaxY（可能在 resize 期间抖动）
- `MessageTableView.updatePinnedState()`：
  - `distanceFromBottom = max(0, docHeight - visibleMaxY)`
  - 通过 `TailFollow.reduce(event: .distanceChanged(distanceFromBottom))` 驱动 `tailFollowState.isFollowingTail`。
- `HushCore/TailFollowStateMachine.swift`：
  - `pinnedDistanceThreshold = 80`（<=80 认为 pinned / following）
  - `programmaticScrollGrace = 0.1`（programmatic scroll 后短时间内 distanceChanged 不会打断 following）

### 3) 现有 inset：MessageTableView 内部 bottom inset = HushSpacing.lg
- `MessageTableView.init`: `scrollView.automaticallyAdjustsContentInsets = false`；`scrollView.contentInsets.bottom = HushSpacing.lg`

## 高概率根因假设（待进一步验证）
- **H1（最吻合症状）**：`layout()` 中 shrink 时的同步 `scrollToBottom()` 发生在“布局/可视区域尚未稳定”的时刻，导致 `scrollRowToVisible` 使用了旧的可视高度/旧 inset，最终让最后一行落在 dock 下方；之后任意一次额外的 bounds/layout 更新（比如点击 table）让滚动补偿再次生效，于是恢复。
- **H2（次高）**：resize 瞬间 `distanceFromBottom` 抖动导致 tail-follow 状态短暂被判定为“用户已上滑”，从而跳过 shrink 时补偿滚动（或滚动后又被状态机抑制）。
- **H3（观感补丁方向）**：bottom inset 较小导致最后一行“贴底”，任何轻微偏差都更明显；增大 inset 能降低出现概率但不解决时序根因。

## 事件链路（基于现有布局结构的推断）
- `ChatDetailPane`：`VStack(spacing: 0)` 上方是 `HotScenePoolRepresentable().frame(maxHeight: .infinity).clipped()`，下方是 `ComposerDock()`。
- `ComposerDock`：`TextEditor` 没有显式 focus handler，但在 macOS 上**获得焦点/插入光标**可能触发 SwiftUI 重新测量（以及输入区高度从 minHeight 向 maxHeight 的变化）。
- 结果：composer 高度变化 → 上方消息列表视图高度 shrink → `MessageTableView.layout()` 触发 shrink 分支 → 同步 `scrollToBottom()`（潜在时序 race）。

## 候选修复方向（需要用户/我们确认优先级）
1) **最小改动**：在 `layout()` 里检测到 shrink + tail-follow 时，不要同步滚动，改为 **defer 到下一轮 runloop（DispatchQueue.main.async / RunLoop.main.perform）**，并做去重/合并。
   - 进一步：defer 的滚动应尽量走 `performScrollToBottom(animated: false, reason: ...)`（或至少先发一次 `.programmaticScrollInitiated`），避免 pinned 判定被 resize 后的 `distanceChanged` 意外打断。
2) **更鲁棒**：shrink 事件里更宽容地判定“仍接近底部”，即使 `userHasScrolledUp` 瞬间翻转，也做一次补偿（`distanceFromBottom <= threshold + epsilon`）。
3) **UI 补丁**：增大 `scrollView.contentInsets.bottom`。
4) **跨组件联动（侵入性更高）**：在 `ComposerDock` 通过 `@FocusState` 识别聚焦变化并向消息列表发通知/回调，让消息列表在聚焦后（且 tail-follow 为真时）再做一次补偿滚动。

## Open Questions（阻塞最终方案选择）
- 仅“获得焦点”也会触发吗？还是必须让 composer 高度变化（32→64）才会复现？
- 复现时：是否正在 streaming（assistant 输出中）？
- 你更偏向：最小改动（defer scroll）优先，还是愿意同时加入“更宽容的 pinned 判定”来增强鲁棒性？

## 用户偏好（confirmed）
- 触发条件（是否必须伴随 composer 高度变化）：不确定
- 修复策略：最小修复（优先 defer + 去重，不扩大战线）
- 测试策略：需要补一条自动化测试（推荐）

## 备注
- 目前还有一条 Oracle 咨询在跑（AppKit scroll compensation 的最佳实践），回到结果后我会把建议合并到这个 draft 里。

## Oracle 建议摘要（已回收，供后续收敛最小实现）
- 典型根因：**同一轮 runloop 中可视区域（clip view/visible rect）变化与 scroll-to-bottom 定位先后发生**，滚动使用了旧几何信息 → 造成底部对齐偏差；“点一下列表就好”本质是触发了下一轮布局/边界更新。
- 最稳妥的共同点（可做最小版）：
  - 把 shrink 时的补偿滚动 **defer 到下一轮**（`DispatchQueue.main.async` 或 `Task.yield()`），并 **coalesce**（每轮最多一次）。
  - 在执行滚动前做一次 `layoutSubtreeIfNeeded()`（只在 pinned 且确实需要校正时），降低“布局未 settle”风险。
  - 避免滚动循环：bounds 监听触发滚动→再触发 bounds；用重入锁/最多一次（或最多两次）稳定化断环。
- 如果发现是 overlay（dock 覆盖在列表上）才需要：将覆盖高度显式建模为 `scrollView.contentInsets.bottom = dockHeight`。
  - 当前代码结构是 `VStack`（看起来更像非 overlay），因此 **默认先不走 inset 建模**，先做 defer 修正。
