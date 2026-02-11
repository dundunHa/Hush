# 04 — Scroll Stability (TailFollow)

滚动稳定性统一由 `MessageTableView` 内的 `TailFollowStateMachine` 管理。

## 目标语义

- 会话切换到有消息线程时，默认展示尾部最新内容。
- assistant 新增消息仅在“仍跟随尾部”时自动贴底。
- user 自己发送消息时强制贴底并恢复跟随态。
- 历史 prepend（上拉加载更早消息）不触发贴底。

## 关键事件

- `conversationSwitched`
- `messageAdded(role:didPrependOlder:)`
- `distanceChanged(_:)`
- `streamingStarted` / `streamingCompleted`
- `programmaticScrollInitiated`

## 关键阈值（见 `TailFollowConfig`）

- pinned distance threshold
- streaming breakaway threshold
- post-streaming grace interval
- programmatic scroll grace

## 视图层实现

- `MessageTableView.updatePinnedState()` 通过 `NSScrollView` 可视区域实时计算距离。
- `handleTailFollowAction(...)` 统一执行滚动动作与埋点。
- `triggerOlderMessagesLoadIfNeeded()` 在接近顶部时触发历史加载并保持锚点稳定。

## 回归重点

- 切换后首帧尾部可见
- streaming 期间不出现频繁跳动
- prepend 后索引与滚动锚点不损坏
